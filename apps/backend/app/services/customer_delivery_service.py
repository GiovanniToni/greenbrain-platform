from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Tuple
import hashlib
import logging
import os
import secrets
import shlex
import shutil
import tarfile
import tempfile
import zipfile



from app.core.config import settings
from app.core.secret_crypto import decrypt_secret
from app.integrations.supabase_client import get_supabase_client
from app.repositories.customer_delivery_repository import (
    get_customer_by_id,
    get_delivery_row,
    mark_bundle_sent,
)
from app.repositories.customer_portal_repository import update_customer_last_download
from app.repositories.customer_source_db_repository import get_source_db_integration
from app.services.customer_runtime_service import create_provisioning_token

RELEASES_ROOT = Path("/opt/greenbrain-platform/releases/customer-local")
CUSTOMER_BUNDLE_OUTPUT_DIR = Path(
    os.getenv(
        "GREENBRAIN_CUSTOMER_BUNDLE_OUTPUT_DIR",
        "/opt/greenbrain-platform/runtime-reports/customer-bundles",
    )
)
CUSTOMER_BUNDLE_RETENTION_DAYS = int(os.getenv("GREENBRAIN_CUSTOMER_BUNDLE_RETENTION_DAYS", "14"))
CUSTOMER_BUNDLE_RETENTION_MIN_KEEP = int(os.getenv("GREENBRAIN_CUSTOMER_BUNDLE_RETENTION_MIN_KEEP", "20"))

logger = logging.getLogger("greenbrain.customer_delivery")


def _version_key(version_name: str) -> Tuple[int, ...]:
    parts = []
    for chunk in version_name.split("."):
        try:
            parts.append(int(chunk))
        except ValueError:
            parts.append(0)
    return tuple(parts)


def _find_release_bundle(version: str) -> Path | None:
    version = (version or "").strip()
    if not version:
        return None
    bundle = RELEASES_ROOT / version / "GreenBrain-Installer.zip"
    if bundle.exists() and bundle.is_file():
        return bundle
    return None


def _tenant_public_host(tenant_code: str) -> str:
    safe = (tenant_code or "").strip().replace("_", "-")
    return f"{safe}.greenbrain.it" if safe else "CHANGE_ME.greenbrain.it"


def _find_latest_release_bundle() -> Path | None:
    if not RELEASES_ROOT.exists() or not RELEASES_ROOT.is_dir():
        return None

    candidates: list[tuple[Tuple[int, ...], Path]] = []

    for entry in RELEASES_ROOT.iterdir():
        if not entry.is_dir():
            continue

        version = entry.name.strip()
        bundle = entry / "GreenBrain-Installer.zip"
        if bundle.exists() and bundle.is_file():
            candidates.append((_version_key(version), bundle))

    if not candidates:
        return None

    candidates.sort(key=lambda item: item[0], reverse=True)
    return candidates[0][1]




def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _write_sha256_file(path: Path) -> str:
    sha256 = _sha256_file(path)
    checksum_path = path.with_name(path.name + ".sha256")
    checksum_path.write_text(f"{sha256}  {path.name}\n")
    return sha256


def _safe_customer_bundle_output_files() -> list[Path]:
    if not CUSTOMER_BUNDLE_OUTPUT_DIR.exists():
        return []

    patterns = (
        "GreenBrain-Installer-*.zip",
        "GreenBrain-Installer-*.zip.sha256",
        "customer-local-*.tar.gz",
        "customer-local-*.tar.gz.sha256",
    )

    files: list[Path] = []
    for pattern in patterns:
        files.extend(
            p for p in CUSTOMER_BUNDLE_OUTPUT_DIR.glob(pattern)
            if p.is_file() and p.parent == CUSTOMER_BUNDLE_OUTPUT_DIR
        )

    return sorted(set(files), key=lambda item: item.stat().st_mtime, reverse=True)


def cleanup_customer_bundle_output_dir() -> dict[str, int]:
    CUSTOMER_BUNDLE_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    files = _safe_customer_bundle_output_files()
    now_ts = datetime.now(timezone.utc).timestamp()
    max_age_seconds = max(CUSTOMER_BUNDLE_RETENTION_DAYS, 1) * 86400
    min_keep = max(CUSTOMER_BUNDLE_RETENTION_MIN_KEEP, 0)

    removed = 0
    kept = 0

    for idx, file_path in enumerate(files):
        age_seconds = now_ts - file_path.stat().st_mtime
        keep_by_count = idx < min_keep
        keep_by_age = age_seconds <= max_age_seconds

        if keep_by_count or keep_by_age:
            kept += 1
            continue

        try:
            file_path.unlink()
            removed += 1
        except OSError as exc:
            logging.getLogger("uvicorn.error").warning(
                "customer_bundle_cleanup_failed path=%s error=%s",
                str(file_path),
                exc,
            )

    if removed:
        logging.getLogger("uvicorn.error").warning(
            "customer_bundle_cleanup removed=%s kept=%s retention_days=%s min_keep=%s dir=%s",
            removed,
            kept,
            CUSTOMER_BUNDLE_RETENTION_DAYS,
            min_keep,
            str(CUSTOMER_BUNDLE_OUTPUT_DIR),
        )

    return {"removed": removed, "kept": kept}


def _extract_release_version_from_bundle_path(bundle_path: Path) -> str | None:
    name = bundle_path.name.strip()
    prefix = "customer-local-"
    suffix = ".tar.gz"
    if name.startswith(prefix) and name.endswith(suffix):
        return name[len(prefix):-len(suffix)] or None
    parent = bundle_path.parent.name.strip()
    if parent:
        return parent.replace("greenbrain-customer-local-", "") or None
    return None


def get_latest_available_release_version() -> str | None:
    bundle = _find_latest_release_bundle()
    if not bundle:
        return None
    return _extract_release_version_from_bundle_path(bundle)



def _safe_env_value(value: Any) -> str:
    return str(value or "").replace("\n", " ").replace("\r", " ").strip()




def _get_cloud_password_seed_for_customer(customer_profile: Dict[str, Any]) -> Dict[str, Any]:
    email = (
        customer_profile.get("portal_user_email")
        or customer_profile.get("contact_email")
        or customer_profile.get("email")
        or ""
    ).strip().lower()

    if not email:
        return {}

    try:
        client = get_supabase_client()
        result = (
            client.table("greenbrain_users")
            .select(
                "hashed_password,password_version,password_changed_at,"
                "password_last_sync_status"
            )
            .eq("email", email)
            .limit(1)
            .execute()
        )
        rows = result.data or []
        if not rows:
            return {}

        row = rows[0] or {}
        hashed_password = (row.get("hashed_password") or "").strip()
        if not hashed_password:
            return {}

        return {
            "hashed_password": hashed_password,
            "password_version": row.get("password_version"),
            "password_changed_at": row.get("password_changed_at"),
            "password_last_sync_status": row.get("password_last_sync_status") or "synced",
        }
    except Exception:
        return {}



def _quote_env_value(value: Any) -> str:
    raw = "" if value is None else str(value)
    return shlex.quote(raw)

def _render_customer_env(base_env: str, customer_profile: Dict[str, Any], temp_password: str) -> str:
    tenant_code = _safe_env_value(customer_profile.get("tenant_code"))
    tenant_name = _safe_env_value(
        customer_profile.get("company_name")
        or customer_profile.get("contact_name")
        or tenant_code
    )
    email = _safe_env_value(customer_profile.get("portal_user_email") or customer_profile.get("contact_email"))
    full_name = _safe_env_value(customer_profile.get("contact_name") or customer_profile.get("company_name") or email)
    home_host = _tenant_public_host(tenant_code)
    db_name = f"greenbrain_{tenant_code}" if tenant_code else "greenbrain"
    db_user = f"greenbrain_{tenant_code}" if tenant_code else "greenbrain"
    db_password = secrets.token_urlsafe(24)

    overrides = {
        "APP_ENV": "client-local",
        "TENANT_CODE": tenant_code,
        "TENANT_NAME": tenant_name,
        "TENANT_HOST": home_host,
        "POSTGRES_HOST": "postgres",
        "POSTGRES_PORT": "5432",
        "POSTGRES_DB": db_name,
        "POSTGRES_USER": db_user,
        "POSTGRES_PASSWORD": db_password,
        "POSTGRES_SSLMODE": "disable",
        "DATABASE_URL": f"postgresql://{db_user}:{db_password}@postgres:5432/{db_name}",
        "JWT_EXPIRE_MINUTES": "60",
        "LOCAL_BACKEND_PORT": "8008",
        "LOCAL_FRONTEND_PORT": "8088",
        "CENTRAL_AUTH_URL": "https://www.greenbrain.it",
        "CENTRAL_TENANT_CODE": tenant_code,
        "REMOTE_ACCESS_MODE": "reverse-tunnel",
        "TUNNEL_ENABLED": "true",
        "LOCAL_CUSTOMER_EMAIL": email,
        "LOCAL_CUSTOMER_FULL_NAME": full_name,
        "LOCAL_CUSTOMER_TEMP_PASSWORD": temp_password,
        "LOCAL_CUSTOMER_PASSWORD_HASH": (customer_profile.get("local_customer_password_hash") or ""),
        "LOCAL_CUSTOMER_PASSWORD_MODE": (customer_profile.get("local_customer_password_mode") or ("temporary_password" if temp_password else "cloud_password")),
        "LOCAL_CUSTOMER_PASSWORD_VERSION": (customer_profile.get("local_customer_password_version") or ""),
        "LOCAL_CUSTOMER_PASSWORD_CHANGED_AT": (customer_profile.get("local_customer_password_changed_at") or ""),
        "LOCAL_CUSTOMER_PASSWORD_SYNC_STATUS": (customer_profile.get("local_customer_password_sync_status") or ""),
        "LOCAL_CUSTOMER_PASSWORD_SEED_SOURCE": (customer_profile.get("local_customer_password_seed_source") or ""),
        "LOCAL_CUSTOMER_TENANT_CODE": tenant_code,
        "LOCAL_CUSTOMER_HOME_HOST": home_host,
        "LOCAL_CUSTOMER_HOME_PATH": "/dashboard",
        "LOCAL_CUSTOMER_USER_ROLE": "customer_admin",
    }

    lines = []
    seen = set()
    for line in base_env.splitlines():
        key = line.split("=", 1)[0].strip() if "=" in line and not line.strip().startswith("#") else None
        if key in overrides:
            lines.append(f"{key}={_quote_env_value(overrides[key])}")
            seen.add(key)
        else:
            lines.append(line)

    lines.append("")
    lines.append("# Runtime customer local user provisioning - generated by GreenBrain cloud")
    for key, value in overrides.items():
        if key not in seen:
            lines.append(f"{key}={_quote_env_value(value)}")

    return "\n".join(lines).rstrip() + "\n"

def _replace_or_append_env_value(text: str, key: str, value: str) -> str:
    lines = []
    found = False
    for line in text.splitlines():
        if line.startswith(f"{key}="):
            lines.append(f"{key}={_quote_env_value(value)}")
            found = True
        else:
            lines.append(line)
    if not found:
        lines.append(f"{key}={_quote_env_value(value)}")
    return "\n".join(lines).rstrip() + "\n"



def _source_db_bool(value: Any, *, default: bool = False) -> str:
    if value is None:
        return "yes" if default else "no"
    if isinstance(value, bool):
        return "yes" if value else "no"
    raw = str(value).strip().lower()
    if raw in {"1", "true", "yes", "y", "on"}:
        return "yes"
    if raw in {"0", "false", "no", "n", "off"}:
        return "no"
    return "yes" if default else "no"


def _render_source_db_env_for_customer(customer_profile: Dict[str, Any]) -> str | None:
    """Render overlay/env/source-db.env for a personalized bundle.

    Security rules:
    - only render when the cloud config is formally valid;
    - only decrypt the password inside the server-side bundle builder;
    - never log or return the password elsewhere;
    - fail closed: if anything is incomplete, skip prefill and let the wizard/manual flow handle it.
    """
    customer_id = _safe_env_value(customer_profile.get("customer_id"))
    tenant_code = _safe_env_value(customer_profile.get("tenant_code"))

    if not customer_id:
        return None

    try:
        integration = get_source_db_integration(customer_id, include_secret=True)
    except Exception:
        return None

    if not integration:
        return None

    if (integration.get("formal_validation_status") or "").strip() != "formal_validation_ok":
        return None

    encrypted_password = (integration.get("db_password_encrypted") or "").strip()
    if not encrypted_password:
        return None

    try:
        source_db_password = decrypt_secret(encrypted_password)
    except Exception:
        return None

    required = {
        "SOURCE_DB_HOST": integration.get("db_host"),
        "SOURCE_DB_NAME": integration.get("db_name"),
        "SOURCE_DB_USER": integration.get("db_username"),
        "SOURCE_DB_PASSWORD": source_db_password,
    }
    if any(not _safe_env_value(value) for value in required.values()):
        return None

    source_client_code = (
        integration.get("source_client_code")
        or tenant_code
        or customer_id
        or "greenhouse"
    )

    values = {
        "SOURCE_DB_ENABLED": "yes",
        "SOURCE_DB_TYPE": integration.get("db_type") or "sqlserver",
        "SOURCE_CLIENT_CODE": source_client_code,
        "SOURCE_DB_CLIENT_CODE": source_client_code,
        "SOURCE_DB_HOST": integration.get("db_host"),
        "SOURCE_DB_PORT": integration.get("db_port") or "1433",
        "SOURCE_DB_NAME": integration.get("db_name"),
        "SOURCE_DB_USER": integration.get("db_username"),
        "SOURCE_DB_PASSWORD": source_db_password,
        "SOURCE_DB_SCHEMA": integration.get("db_schema") or "dbo",
        "SOURCE_DB_VIEW": integration.get("db_view_name") or "GREENBRAIN_VIEW_SALES_RAW",
        "SOURCE_DB_ENCRYPT": _source_db_bool(integration.get("db_encrypt"), default=False),
        "SOURCE_DB_TRUST_CERT": _source_db_bool(integration.get("db_trust_server_certificate"), default=True),
    }

    lines = [
        "# GreenBrain Source DB config",
        "# Generated by GreenBrain cloud from formally validated customer integration.",
        "# This file is local-only inside the personalized installer bundle.",
    ]
    for key, value in values.items():
        lines.append(f"{key}={_quote_env_value(value)}")

    return "\n".join(lines).rstrip() + "\n"

def _build_personalized_bundle(source_bundle: Path, customer_profile: Dict[str, Any]) -> Path:
    customer_id = _safe_env_value(customer_profile.get("customer_id"))
    tenant_code = _safe_env_value(customer_profile.get("tenant_code"))
    tenant_name = _safe_env_value(customer_profile.get("company_name") or customer_profile.get("contact_name") or tenant_code)

    if not customer_id or not tenant_code:
        raise RuntimeError("customer_profile_missing_customer_id_or_tenant_code")

    version = _extract_release_version_from_bundle_path(source_bundle) or "unknown"
    out_dir = CUSTOMER_BUNDLE_OUTPUT_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    cleanup_customer_bundle_output_dir()

    token_result = create_provisioning_token(
        customer_id=customer_id,
        tenant_code=tenant_code,
        expires_days=14,
    )
    provisioning_token = token_result["token"]

    cloud_password_seed = _get_cloud_password_seed_for_customer(customer_profile)
    if cloud_password_seed.get("hashed_password"):
        customer_profile = {
            **customer_profile,
            "local_customer_password_hash": cloud_password_seed.get("hashed_password") or "",
            "local_customer_password_mode": "cloud_password",
            "local_customer_password_version": cloud_password_seed.get("password_version") or "",
            "local_customer_password_changed_at": cloud_password_seed.get("password_changed_at") or "",
            "local_customer_password_sync_status": cloud_password_seed.get("password_last_sync_status") or "synced",
            "local_customer_password_seed_source": "cloud_seed",
        }
        temp_password = ""
    else:
        customer_profile = {
            **customer_profile,
            "local_customer_password_mode": "temporary_password",
        }
        temp_password = secrets.token_urlsafe(18)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    output_bundle = out_dir / f"customer-local-{version}-{tenant_code}-{stamp}.tar.gz"

    with tempfile.TemporaryDirectory(prefix="gb_bundle_") as tmp:
        tmp_path = Path(tmp)
        with tarfile.open(source_bundle, "r:gz") as tar:
            tar.extractall(tmp_path)

        env_candidates = list(tmp_path.rglob("overlay/env/customer-local.env"))
        if env_candidates:
            env_path = env_candidates[0]
            base_env_text = env_path.read_text()
            template_root = env_path.parent.parent.parent
        else:
            example_candidates = list(tmp_path.rglob("env/customer-local.env.example"))
            if not example_candidates:
                raise RuntimeError("customer_env_example_missing")
            example_path = example_candidates[0]
            template_root = example_path.parent.parent
            env_dir = template_root / "overlay" / "env"
            env_dir.mkdir(parents=True, exist_ok=True)
            env_path = env_dir / "customer-local.env"
            base_env_text = example_path.read_text()

        customer_env_text = _render_customer_env(base_env_text, customer_profile, temp_password)
        customer_env_text = _replace_or_append_env_value(customer_env_text, "JWT_SECRET", settings.jwt_secret)
        env_path.write_text(customer_env_text)

        source_db_env_text = _render_source_db_env_for_customer(customer_profile)
        if source_db_env_text:
            source_db_env_path = template_root / "overlay" / "env" / "source-db.env"
            source_db_env_path.parent.mkdir(parents=True, exist_ok=True)
            source_db_env_path.write_text(source_db_env_text)
            source_db_env_path.chmod(0o600)

        runtime_env_candidates = list(tmp_path.rglob("overlay/provisioning/local-runtime.env"))
        if runtime_env_candidates:
            runtime_env_path = runtime_env_candidates[0]
        else:
            runtime_env_example_candidates = list(tmp_path.rglob("overlay/provisioning/local-runtime.env.example"))
            if runtime_env_example_candidates:
                runtime_env_example_path = runtime_env_example_candidates[0]
                runtime_env_path = runtime_env_example_path.with_name("local-runtime.env")
                runtime_env_path.write_text(runtime_env_example_path.read_text())
            else:
                provisioning_dirs = list(tmp_path.rglob("overlay/provisioning"))
                if not provisioning_dirs:
                    provisioning_dir = tmp_path / "package" / "customer-local-template" / "overlay" / "provisioning"
                    provisioning_dir.mkdir(parents=True, exist_ok=True)
                else:
                    provisioning_dir = provisioning_dirs[0]
                runtime_env_path = provisioning_dir / "local-runtime.env"
                runtime_env_path.write_text("""TENANT_CODE=CHANGE_ME
TENANT_NAME='CHANGE_ME'
INSTALLATION_ID=
CONNECTION_MODE=reverse-tunnel
DATA_MODE=local-db-via-tunnel
TUNNEL_PUBLIC_HOST=
PUBLIC_BACKEND_URL=
CENTRAL_AUTH_URL=https://www.greenbrain.it
HEARTBEAT_URL=https://www.greenbrain.it/api/v1/customer-runtime/heartbeat
PROVISIONING_TOKEN=
""")

        runtime_env = runtime_env_path.read_text()
        runtime_env = _replace_or_append_env_value(runtime_env, "TENANT_CODE", tenant_code)
        runtime_env = _replace_or_append_env_value(runtime_env, "TENANT_NAME", tenant_name)
        public_host = _tenant_public_host(tenant_code)
        runtime_env = _replace_or_append_env_value(runtime_env, "TUNNEL_PUBLIC_HOST", public_host)
        runtime_env = _replace_or_append_env_value(runtime_env, "PUBLIC_BACKEND_URL", f"https://{public_host}")
        runtime_env = _replace_or_append_env_value(runtime_env, "CENTRAL_AUTH_URL", "https://www.greenbrain.it")
        runtime_env = _replace_or_append_env_value(runtime_env, "HEARTBEAT_URL", "https://www.greenbrain.it/api/v1/customer-runtime/heartbeat")
        runtime_env = _replace_or_append_env_value(runtime_env, "PROVISIONING_TOKEN", provisioning_token)
        runtime_env_path.write_text(runtime_env)

        with tarfile.open(output_bundle, "w:gz") as tar:
            for child in tmp_path.iterdir():
                tar.add(child, arcname=child.name)

    _write_sha256_file(output_bundle)
    return output_bundle


def _source_tar_for_universal_installer(universal_installer: Path) -> Path | None:
    version = _extract_release_version_from_bundle_path(universal_installer)
    if not version:
        return None
    tar_path = universal_installer.parent / f"customer-local-{version}.tar.gz"
    if tar_path.exists() and tar_path.is_file():
        return tar_path
    return None


def _replace_embedded_archive(script_path: Path, personalized_tar: Path) -> None:
    marker = b"__GREENBRAIN_ARCHIVE_BELOW__\n"
    data = script_path.read_bytes()
    pos = data.find(marker)
    if pos < 0:
        raise RuntimeError(f"embedded_archive_marker_missing: {script_path.name}")
    header = data[: pos + len(marker)]
    script_path.write_bytes(header + personalized_tar.read_bytes())
    script_path.chmod(0o755)


def _build_personalized_universal_installer(
    universal_installer: Path,
    customer_profile: Dict[str, Any],
) -> Path:
    customer_id = _safe_env_value(customer_profile.get("customer_id"))
    tenant_code = _safe_env_value(customer_profile.get("tenant_code"))

    if not customer_id or not tenant_code:
        raise RuntimeError("customer_profile_missing_customer_id_or_tenant_code")

    source_tar = _source_tar_for_universal_installer(universal_installer)
    if not source_tar:
        raise RuntimeError(f"source_tar_missing_for_universal_installer: {universal_installer}")

    version = _extract_release_version_from_bundle_path(universal_installer) or "unknown"
    personalized_tar = _build_personalized_bundle(source_tar, customer_profile)

    stamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    out_root = CUSTOMER_BUNDLE_OUTPUT_DIR
    out_root.mkdir(parents=True, exist_ok=True)
    out_dir = out_root / f"universal-{version}-{tenant_code}-{stamp}"
    out_dir.mkdir(parents=True, exist_ok=True)
    output_zip = out_root / f"GreenBrain-Installer-{version}-{tenant_code}-{stamp}.zip"

    with zipfile.ZipFile(universal_installer, "r") as zin:
        zin.extractall(out_dir)

    for script_name in ("INSTALLA_GREENBRAIN_LINUX.run", "INSTALLA_GREENBRAIN_MAC.command"):
        script_path = out_dir / script_name
        if script_path.exists() and script_path.is_file():
            _replace_embedded_archive(script_path, personalized_tar)

    with zipfile.ZipFile(output_zip, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        for child in sorted(out_dir.iterdir()):
            if child.is_file():
                zout.write(child, arcname=child.name)

    _write_sha256_file(output_zip)
    shutil.rmtree(out_dir, ignore_errors=True)
    return output_zip


def generate_test_bundle_for_customer(customer_id: str) -> Dict[str, Any]:
    """Genera un bundle personalizzato per un cliente senza verificare
    il gate pagamento/slot. Usato solo da endpoint ops (admin)."""
    customer = get_customer_by_id(customer_id)
    if not customer.get("portal_user_email"):
        customer["portal_user_email"] = customer.get("contact_email", "")
    latest_bundle = _find_latest_release_bundle()
    if not latest_bundle:
        raise RuntimeError("no_release_bundle_available")
    personalized = _build_personalized_universal_installer(latest_bundle, customer)
    version = _extract_release_version_from_bundle_path(latest_bundle) or "unknown"
    return {
        "bundle_path": str(personalized),
        "filename": personalized.name,
        "version": version,
    }


def record_bundle_download(customer_profile: Dict[str, Any], bundle: Dict[str, Any]) -> Dict[str, Any]:
    customer_id = (customer_profile.get("customer_id") or "").strip()
    bundle_path = Path(bundle["bundle_path"])
    version = (
        (bundle.get("assigned_release_version") or "").strip()
        or _extract_release_version_from_bundle_path(bundle_path)
    )
    if not customer_id or not version:
        return {
            "customer_id": customer_id or None,
            "last_downloaded_release_version": version,
            "last_downloaded_at": None,
        }

    ts = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    row = update_customer_last_download(
        customer_id=customer_id,
        last_downloaded_release_version=version,
        last_downloaded_at=ts,
    )
    return row

def bundle_download_headers(bundle: Dict[str, Any]) -> Dict[str, str]:
    version = (bundle.get("assigned_release_version") or bundle.get("version") or "").strip()
    source = (bundle.get("source") or "").strip()
    filename = (bundle.get("filename") or Path(bundle.get("bundle_path", "")).name or "GreenBrain-Installer.zip").strip()

    headers = {
        "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
        "Pragma": "no-cache",
        "Expires": "0",
        "X-Accel-Buffering": "no",
        "X-GreenBrain-Bundle-Filename": filename,
    }

    if version:
        headers["X-GreenBrain-Bundle-Version"] = version
    if source:
        headers["X-GreenBrain-Bundle-Source"] = source

    bundle_path = Path(bundle.get("bundle_path", ""))
    if bundle_path.exists() and bundle_path.is_file():
        headers["X-GreenBrain-Bundle-SHA256"] = _sha256_file(bundle_path)

    return headers


def log_bundle_download(
    *,
    actor: str,
    customer_profile: Dict[str, Any],
    bundle: Dict[str, Any],
) -> None:
    bundle_path = Path(bundle["bundle_path"])
    try:
        size_bytes = bundle_path.stat().st_size
    except OSError:
        size_bytes = None

    try:
        sha256 = _sha256_file(bundle_path)
    except OSError:
        sha256 = None

    message = (
        "customer_bundle_download "
        f"actor={actor} "
        f"customer_id={customer_profile.get('customer_id')} "
        f"email={customer_profile.get('portal_user_email') or customer_profile.get('contact_email') or customer_profile.get('email')} "
        f"tenant_code={customer_profile.get('tenant_code')} "
        f"release_version={bundle.get('assigned_release_version') or bundle.get('version')} "
        f"source={bundle.get('source')} "
        f"filename={bundle.get('filename') or bundle_path.name} "
        f"path={str(bundle_path)} "
        f"size_bytes={size_bytes} "
        f"sha256={sha256}"
    )

    logger.info(message)
    logging.getLogger("uvicorn.error").warning(message)


def prepare_delivery_plan(customer_id: str) -> Dict[str, Any]:
    customer = get_customer_by_id(customer_id)

    assigned_release_version = (customer.get("assigned_release_version") or "").strip()
    if not assigned_release_version:
        raise RuntimeError("assigned_release_version_missing")

    tenant_code = (customer.get("tenant_code") or "").strip()
    company_name = (customer.get("company_name") or "").strip()

    return {
        "status": "planned",
        "customer_id": customer_id,
        "tenant_code": tenant_code,
        "company_name": company_name,
        "assigned_release_version": assigned_release_version,
        "message": "Bundle generation must run on host via tools/customer_ops/prepare_assigned_bundle.sh",
    }


def mark_delivery_sent(customer_id: str) -> Dict[str, Any]:
    delivery = get_delivery_row(customer_id)
    if not delivery:
        raise ValueError("delivery_row_missing")
    if not delivery.get("bundle_generated_at"):
        raise ValueError("bundle_not_generated_yet")

    ts = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    row = mark_bundle_sent(customer_id=customer_id, bundle_sent_at=ts)
    return {
        "status": "sent_marked",
        "customer_id": customer_id,
        "bundle_sent_at": row.get("bundle_sent_at", ts),
        "delivery": row,
    }


def resolve_bundle_download(customer_profile: Dict[str, Any], user_agent: str = '') -> Dict[str, Any]:
    payment_saved = customer_profile.get("payment_method_saved") is True
    slot_requested = bool(customer_profile.get("setup_slot_requested_at"))
    slot_confirmed = bool(
        customer_profile.get("setup_slot_confirmed_at")
        or customer_profile.get("setup_slot_scheduled_for")
    )

    if not payment_saved or not slot_requested or not slot_confirmed:
        raise RuntimeError("bundle_not_ready")

    is_macos = "macintosh" in (user_agent or "").lower() or "mac os x" in (user_agent or "").lower()

    # 1) Preferred source: latest one-click release available on host
    latest_bundle = _find_latest_release_bundle()
    if is_macos and latest_bundle:
        mac_zip = latest_bundle.parent / "INSTALLA_GREENBRAIN_MAC.zip"
        if mac_zip.exists() and mac_zip.is_file():
            latest_version = _extract_release_version_from_bundle_path(latest_bundle)
            return {
                "bundle_path": str(mac_zip),
                "filename": "INSTALLA_GREENBRAIN_MAC.zip",
                "internal_filename": mac_zip.name,
                "source": "oneclick_macos_latest_release",
                "assigned_release_version": latest_version,
            }
    if latest_bundle and latest_bundle.exists() and latest_bundle.is_file():
        latest_version = _extract_release_version_from_bundle_path(latest_bundle)
        personalized_bundle = _build_personalized_universal_installer(latest_bundle, customer_profile)
        return {
            "bundle_path": str(personalized_bundle),
            "filename": personalized_bundle.name,
            "internal_filename": personalized_bundle.name,
            "source": "personalized_universal_installer_latest_release",
            "assigned_release_version": latest_version,
        }

    # 2) Fallback: assigned one-click release for this customer
    assigned_version = (customer_profile.get("assigned_release_version") or "").strip()
    assigned_bundle = _find_release_bundle(assigned_version)
    if assigned_bundle and assigned_bundle.exists() and assigned_bundle.is_file():
        return {
            "bundle_path": str(assigned_bundle),
            "filename": "GreenBrain-Installer.zip",
            "internal_filename": assigned_bundle.name,
            "source": "universal_installer_assigned_release_fallback",
            "assigned_release_version": assigned_version,
        }

    # 2) Fallback: per-customer prepared bundle path, if available
    delivery = customer_profile.get("delivery") or {}
    bundle_local_path = (delivery.get("bundle_local_path") or "").strip()
    if bundle_local_path:
        p = Path(bundle_local_path)
        if p.exists() and p.is_file():
            return {
                "bundle_path": str(p),
                "filename": p.name,
                "source": "customer_bundle",
            }
        raise RuntimeError(f"bundle_file_missing: {bundle_local_path}")

    raise RuntimeError("bundle_not_ready")
