from __future__ import annotations

from datetime import datetime, timezone, timedelta
from typing import Any, Dict
import hashlib
import secrets

from app.repositories.customer_source_db_repository import update_source_db_technical_test_result

from app.repositories.customer_runtime_repository import (
    get_customer_by_tenant_code,
    get_runtime_status_by_tenant,
    update_customer_runtime_fields,
    upsert_runtime_connection,
    upsert_runtime_installation,
    upsert_tenant,
    insert_runtime_token,
    get_active_runtime_token_by_hash,
    get_runtime_token_by_hash,
    revoke_active_runtime_tokens_by_customer,
    mark_runtime_token_used,
    get_pending_password_sync_for_runtime,
    ack_password_sync_for_runtime,
)


def _now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def create_provisioning_token(customer_id: str, tenant_code: str, expires_days: int = 14) -> Dict[str, Any]:
    if not customer_id:
        raise RuntimeError("customer_id_missing")
    if not tenant_code:
        raise RuntimeError("tenant_code_missing")

    revoke_active_runtime_tokens_by_customer(customer_id, tenant_code)

    raw_token = "gbp_" + secrets.token_urlsafe(32)
    token_hash = _hash_token(raw_token)
    now = datetime.now(timezone.utc).replace(microsecond=0)
    expires_at = now + timedelta(days=expires_days)

    row = insert_runtime_token({
        "customer_id": customer_id,
        "tenant_code": tenant_code,
        "token_hash": token_hash,
        "token_hint": raw_token[-6:],
        "purpose": "runtime_bind",
        "status": "active",
        "expires_at": expires_at.isoformat(),
    })

    return {
        "status": "created",
        "token": raw_token,
        "token_hint": raw_token[-6:],
        "expires_at": expires_at.isoformat(),
        "row": row,
    }



def _validate_runtime_sync_token(raw_token: str | None, tenant_code: str, installation_id: str) -> Dict[str, Any]:
    if not raw_token:
        raise RuntimeError("runtime_token_missing")

    token_hash = _hash_token(raw_token.strip())
    row = get_runtime_token_by_hash(token_hash)
    if not row:
        raise RuntimeError("runtime_token_invalid")

    if (row.get("tenant_code") or "").strip() != tenant_code:
        raise RuntimeError("runtime_token_tenant_mismatch")

    status = (row.get("status") or "").strip().lower()
    used_by_installation_id = (row.get("used_by_installation_id") or "").strip()

    if status == "used" and used_by_installation_id and used_by_installation_id != installation_id:
        raise RuntimeError("runtime_token_installation_mismatch")

    if status not in {"active", "used"}:
        raise RuntimeError("runtime_token_invalid_status")

    expires_at = row.get("expires_at")
    if expires_at:
        exp = datetime.fromisoformat(str(expires_at).replace("Z", "+00:00"))
        if exp < datetime.now(timezone.utc):
            raise RuntimeError("runtime_token_expired")

    return row


def _validate_provisioning_token(raw_token: str | None, tenant_code: str, installation_id: str) -> Dict[str, Any]:
    if not raw_token:
        raise RuntimeError("provisioning_token_missing")

    token_hash = _hash_token(raw_token.strip())

    # Register must be idempotent for installer retry/update on the same runtime.
    # Fresh first registration consumes an active token.
    # A retry with the same already-used token is valid only for the same installation_id.
    row = get_runtime_token_by_hash(token_hash)
    if not row:
        raise RuntimeError("provisioning_token_invalid")

    if (row.get("tenant_code") or "").strip() != tenant_code:
        raise RuntimeError("provisioning_token_tenant_mismatch")

    status = (row.get("status") or "").strip().lower()
    used_by_installation_id = (row.get("used_by_installation_id") or "").strip()

    if status == "used":
        if used_by_installation_id and used_by_installation_id == installation_id:
            return row
        raise RuntimeError("provisioning_token_installation_mismatch")

    if status != "active":
        raise RuntimeError("provisioning_token_invalid_status")

    expires_at = row.get("expires_at")
    if expires_at:
        exp = datetime.fromisoformat(str(expires_at).replace("Z", "+00:00"))
        if exp < datetime.now(timezone.utc):
            raise RuntimeError("provisioning_token_expired")

    mark_runtime_token_used(
        token_id=row["token_id"],
        installation_id=installation_id,
        used_at=_now_iso(),
    )
    return row



def register_runtime(payload: Dict[str, Any], provisioning_token: str | None = None) -> Dict[str, Any]:
    tenant_code = (payload.get("tenant_code") or "").strip()
    installation_id = (payload.get("installation_id") or "").strip()

    if not tenant_code:
        raise RuntimeError("tenant_code_missing")
    if not installation_id:
        raise RuntimeError("installation_id_missing")

    token_row = _validate_provisioning_token(
        raw_token=provisioning_token or payload.get("provisioning_token"),
        tenant_code=tenant_code,
        installation_id=installation_id,
    )

    token_customer_id = token_row.get("customer_id")
    customer = get_customer_by_tenant_code(tenant_code)
    customer_id = token_customer_id or (customer.get("customer_id") if customer else None)

    public_backend_url = (payload.get("public_backend_url") or "").strip() or None
    local_backend_url = (payload.get("local_backend_url") or "").strip() or None
    tunnel_public_host = (payload.get("tunnel_public_host") or "").strip() or None
    version = (payload.get("version") or payload.get("installed_release_version") or "").strip() or None

    tenant = upsert_tenant({
        "tenant_code": tenant_code,
        "tenant_name": payload.get("tenant_name") or (customer or {}).get("company_name") or tenant_code,
        "access_mode": "local-runtime",
        "status": "active",
        "login_host": "www.greenbrain.it",
        "app_host": tunnel_public_host or f"{tenant_code}.greenbrain.it",
        "backend_base_url": public_backend_url,
        "runtime_origin": "customer-local",
        "data_mode": payload.get("data_mode") or "local-db-via-tunnel",
        "notes": "Registered from customer-local runtime",
    })

    installation = upsert_runtime_installation({
        "installation_id": installation_id,
        "customer_id": customer_id,
        "tenant_code": tenant_code,
        "installation_label": payload.get("installation_label") or "default",
        "runtime_mode": "customer-local",
        "connection_mode": payload.get("connection_mode") or "reverse-tunnel",
        "data_mode": payload.get("data_mode") or "local-db-via-tunnel",
        "installed_release_version": version,
        "local_agent_version": version,
        "local_backend_url": local_backend_url,
        "public_backend_url": public_backend_url,
        "tunnel_public_host": tunnel_public_host,
        "provisioning_status": "registered",
        "runtime_health": payload.get("runtime_health") or "unknown",
        "notes": "Runtime registered",
    })

    runtime_connection = upsert_runtime_connection({
        "tenant_code": tenant_code,
        "connection_mode": payload.get("connection_mode") or "reverse-tunnel",
        "sync_enabled": bool(payload.get("sync_enabled", False)),
        "sync_frequency_minutes": payload.get("sync_frequency_minutes"),
        "last_sync_status": payload.get("last_sync_status"),
        "local_agent_version": version,
        "runtime_health": payload.get("runtime_health") or "unknown",
        "installation_id": installation_id,
        "public_backend_url": public_backend_url,
        "local_backend_url": local_backend_url,
        "notes": "Runtime registered",
    })

    if customer_id:
        update_customer_runtime_fields(customer_id, {
            "runtime_connection_status": "registered",
            "latest_installation_id": installation_id,
            "installed_release_version": version,
        })

    return {
        "status": "registered",
        "tenant": tenant,
        "runtime_connection": runtime_connection,
        "installation": installation,
    }


def heartbeat_runtime(payload: Dict[str, Any]) -> Dict[str, Any]:
    tenant_code = (payload.get("tenant_code") or "").strip()
    installation_id = (payload.get("installation_id") or "").strip()

    if not tenant_code:
        raise RuntimeError("tenant_code_missing")
    if not installation_id:
        raise RuntimeError("installation_id_missing")

    now_iso = _now_iso()
    runtime = payload.get("runtime") or {}
    runtime_health = (
        runtime.get("backend_health")
        or payload.get("runtime_health")
        or "unknown"
    )

    customer = get_customer_by_tenant_code(tenant_code)
    customer_id = customer.get("customer_id") if customer else None

    version = (payload.get("version") or payload.get("installed_release_version") or "").strip() or None
    connection_mode = payload.get("connection_mode") or "reverse-tunnel"
    data_mode = payload.get("data_mode") or "local-db-via-tunnel"
    public_backend_url = (payload.get("public_backend_url") or "").strip() or None
    local_backend_url = (payload.get("local_backend_url") or "").strip() or None
    tunnel_public_host = (payload.get("tunnel_public_host") or "").strip() or None

    tenant = upsert_tenant({
        "tenant_code": tenant_code,
        "tenant_name": payload.get("tenant_name") or (customer or {}).get("company_name") or tenant_code,
        "access_mode": "local-runtime",
        "status": "active",
        "login_host": "www.greenbrain.it",
        "app_host": tunnel_public_host or f"{tenant_code}.greenbrain.it",
        "backend_base_url": public_backend_url,
        "runtime_origin": "customer-local",
        "data_mode": data_mode,
        "notes": "Auto-created/updated from customer-local heartbeat",
    })

    installation = upsert_runtime_installation({
        "installation_id": installation_id,
        "customer_id": customer_id,
        "tenant_code": tenant_code,
        "installation_label": payload.get("installation_label") or "default",
        "runtime_mode": "customer-local",
        "connection_mode": connection_mode,
        "data_mode": data_mode,
        "installed_release_version": version,
        "local_agent_version": version,
        "local_backend_url": local_backend_url,
        "public_backend_url": public_backend_url,
        "tunnel_public_host": tunnel_public_host,
        "runtime_health": runtime_health,
        "last_heartbeat_at": now_iso,
        "last_heartbeat_payload": payload,
        "last_sync_status": payload.get("last_sync_status"),
        "provisioning_status": "active",
    })

    runtime_connection = upsert_runtime_connection({
        "tenant_code": tenant_code,
        "connection_mode": connection_mode,
        "sync_enabled": bool(payload.get("sync_enabled", False)),
        "sync_frequency_minutes": payload.get("sync_frequency_minutes"),
        "last_sync_status": payload.get("last_sync_status"),
        "local_agent_version": version,
        "runtime_health": runtime_health,
        "installation_id": installation_id,
        "public_backend_url": public_backend_url,
        "local_backend_url": local_backend_url,
        "last_heartbeat_at": now_iso,
        "last_heartbeat_payload": payload,
        "notes": "Runtime heartbeat",
    })

    if customer_id:
        update_customer_runtime_fields(customer_id, {
            "runtime_connection_status": runtime_health,
            "latest_installation_id": installation_id,
            "last_runtime_heartbeat_at": now_iso,
            "installed_release_version": version,
        })

    actions: list[Dict[str, Any]] = []
    pending_password_sync = get_pending_password_sync_for_runtime(tenant_code)
    if pending_password_sync:
        actions.append({
            "type": "password_sync_required",
            "password_version": pending_password_sync.get("password_version"),
            "email": pending_password_sync.get("email"),
            "required_at": pending_password_sync.get("password_sync_required_at"),
        })

    return {
        "status": "heartbeat_received",
        "tenant": tenant,
        "installation": installation,
        "runtime_connection": runtime_connection,
        "actions": actions,
    }


def get_status(tenant_code: str) -> Dict[str, Any]:
    return get_runtime_status_by_tenant(tenant_code)



def get_pending_password_sync(payload: Dict[str, Any], runtime_token: str | None = None) -> Dict[str, Any]:
    tenant_code = (payload.get("tenant_code") or "").strip()
    installation_id = (payload.get("installation_id") or "").strip()

    if not tenant_code:
        raise RuntimeError("tenant_code_missing")
    if not installation_id:
        raise RuntimeError("installation_id_missing")

    _validate_runtime_sync_token(runtime_token or payload.get("provisioning_token"), tenant_code, installation_id)

    pending = get_pending_password_sync_for_runtime(tenant_code)
    if not pending:
        return {
            "status": "no_pending_password_sync",
            "has_pending": False,
            "tenant_code": tenant_code,
            "installation_id": installation_id,
        }

    return {
        "status": "pending_password_sync",
        "has_pending": True,
        "tenant_code": tenant_code,
        "installation_id": installation_id,
        "user_id": str(pending.get("id")),
        "email": pending.get("email"),
        "hashed_password": pending.get("hashed_password"),
        "password_version": pending.get("password_version"),
        "password_changed_at": pending.get("password_changed_at"),
        "password_sync_required_at": pending.get("password_sync_required_at"),
    }


def ack_password_sync(payload: Dict[str, Any], runtime_token: str | None = None) -> Dict[str, Any]:
    tenant_code = (payload.get("tenant_code") or "").strip()
    installation_id = (payload.get("installation_id") or "").strip()
    user_id = (payload.get("user_id") or "").strip()
    status = (payload.get("status") or "").strip().lower()
    error = payload.get("error")
    password_version = payload.get("password_version")

    if not tenant_code:
        raise RuntimeError("tenant_code_missing")
    if not installation_id:
        raise RuntimeError("installation_id_missing")
    if not user_id:
        raise RuntimeError("user_id_missing")
    if status not in {"synced", "failed"}:
        raise RuntimeError("password_sync_status_invalid")
    if password_version is None:
        raise RuntimeError("password_version_missing")

    _validate_runtime_sync_token(runtime_token or payload.get("provisioning_token"), tenant_code, installation_id)

    result = ack_password_sync_for_runtime(
        user_id=user_id,
        tenant_code=tenant_code,
        password_version=int(password_version),
        status=status,
        error=error,
    )

    return {
        "status": f"password_sync_{status}",
        "tenant_code": tenant_code,
        "installation_id": installation_id,
        "password_version": int(password_version),
        "ack": result,
    }

def ack_source_db_technical_check(payload: Dict[str, Any], runtime_token: str | None = None) -> Dict[str, Any]:
    tenant_code = (payload.get("tenant_code") or "").strip()
    installation_id = (payload.get("installation_id") or "").strip()
    status = (payload.get("status") or "").strip()

    if not tenant_code:
        raise RuntimeError("tenant_code_missing")
    if not installation_id:
        raise RuntimeError("installation_id_missing")
    if status not in {"technical_test_ok", "technical_test_failed"}:
        raise RuntimeError("source_db_technical_test_status_invalid")

    _validate_runtime_sync_token(runtime_token or payload.get("provisioning_token"), tenant_code, installation_id)

    customer = get_customer_by_tenant_code(tenant_code)
    customer_id = customer.get("customer_id") if customer else None
    if not customer_id:
        raise RuntimeError("customer_not_found")

    now_iso = _now_iso()
    result = payload.get("result") or {}
    report = (payload.get("report") or "").strip()
    error = (payload.get("error") or "").strip() or None

    update_payload = {
        "technical_test_status": status,
        "technical_test_report": report or None,
        "technical_test_result": result,
        "technical_test_at": now_iso,
        "last_error_report": error if status == "technical_test_failed" else None,
        "last_error_at": now_iso if status == "technical_test_failed" else None,
        "updated_at": now_iso,
    }

    update_source_db_technical_test_result(customer_id, update_payload)

    return {
        "status": "source_db_technical_test_recorded",
        "tenant_code": tenant_code,
        "installation_id": installation_id,
        "technical_test_status": status,
        "technical_test_at": now_iso,
    }

