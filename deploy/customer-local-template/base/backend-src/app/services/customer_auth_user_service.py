from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any, Dict
from urllib.parse import quote_plus

from sqlalchemy import create_engine, inspect, text

from app.core.security import hash_password


def _required_env(name: str) -> str:
    value = (os.getenv(name) or "").strip()
    if not value:
        raise RuntimeError(f"missing_env:{name}")
    return value


def _build_auth_engine():
    host = _required_env("AUTH_DB_HOST")
    port = (os.getenv("AUTH_DB_PORT") or "5432").strip()
    dbname = _required_env("AUTH_DB_NAME")
    user = _required_env("AUTH_DB_USER")
    password = _required_env("AUTH_DB_PASSWORD")

    url = (
        f"postgresql+psycopg://{quote_plus(user)}:{quote_plus(password)}"
        f"@{host}:{port}/{dbname}"
    )
    return create_engine(
        url,
        future=True,
        pool_pre_ping=True,
        pool_size=2,
        max_overflow=0,
        pool_timeout=10,
        pool_recycle=300,
    )


def _find_user_table(engine) -> tuple[str, set[str]]:
    insp = inspect(engine)

    for table_name in insp.get_table_names():
        cols = {c["name"] for c in insp.get_columns(table_name)}
        if {"email", "hashed_password", "is_active"}.issubset(cols):
            return table_name, cols

    raise RuntimeError("auth_user_table_not_found")


def provision_customer_auth_user(
    *,
    email: str,
    password: str | None = None,
    password_hash: str | None = None,
    full_name: str | None,
    tenant_code: str,
    home_host: str,
    home_path: str,
    user_role: str,
    password_version: int | None = None,
    password_changed_at: str | None = None,
    password_seed_source: str | None = None,
    password_sync_status: str | None = None,
) -> Dict[str, Any]:
    engine = _build_auth_engine()
    table_name, cols = _find_user_table(engine)

    clean_password_hash = (password_hash or "").strip()
    clean_password = (password or "").strip()

    if clean_password_hash:
        hashed_password = clean_password_hash
    elif clean_password:
        hashed_password = hash_password(clean_password)
    else:
        raise RuntimeError("missing_password_or_hash")

    is_cloud_seed = bool(clean_password_hash)
    now_iso = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    seed_password_version = int(password_version or 1)
    seed_password_changed_at = password_changed_at or (now_iso if is_cloud_seed else None)
    seed_password_source = password_seed_source or ("cloud_seed" if is_cloud_seed else "initial")
    seed_password_sync_status = password_sync_status or ("synced" if is_cloud_seed else "not_required")

    payload: Dict[str, Any] = {
        "email": email.strip().lower(),
        "hashed_password": hashed_password,
        "full_name": (full_name or "").strip() or None,
        "is_active": True,
    }

    if "is_admin" in cols:
        payload["is_admin"] = False
    if "tenant_code" in cols:
        payload["tenant_code"] = tenant_code
    if "home_host" in cols:
        payload["home_host"] = home_host
    if "home_path" in cols:
        payload["home_path"] = home_path
    if "user_role" in cols:
        payload["user_role"] = user_role
    if "can_access_app" in cols:
        payload["can_access_app"] = True

    if "password_version" in cols:
        payload["password_version"] = seed_password_version
    if "password_changed_at" in cols:
        payload["password_changed_at"] = seed_password_changed_at
    if "password_change_source" in cols:
        payload["password_change_source"] = seed_password_source
    if "password_sync_required_at" in cols:
        payload["password_sync_required_at"] = None
    if "password_last_sync_status" in cols:
        payload["password_last_sync_status"] = seed_password_sync_status
    if "password_last_synced_at" in cols:
        payload["password_last_synced_at"] = now_iso if is_cloud_seed else None
    if "password_last_sync_attempt_at" in cols:
        payload["password_last_sync_attempt_at"] = now_iso if is_cloud_seed else None
    if "password_last_sync_error" in cols:
        payload["password_last_sync_error"] = None

    with engine.begin() as conn:
        existing = conn.execute(
            text(f"select email from {table_name} where email = :email limit 1"),
            {"email": payload["email"]},
        ).mappings().first()

        if existing:
            set_parts = [f"{key} = :{key}" for key in payload.keys() if key != "email"]
            conn.execute(
                text(f"update {table_name} set {', '.join(set_parts)} where email = :email"),
                payload,
            )
        else:
            insert_cols = ", ".join(payload.keys())
            insert_vals = ", ".join(f":{key}" for key in payload.keys())
            conn.execute(
                text(f"insert into {table_name} ({insert_cols}) values ({insert_vals})"),
                payload,
            )

        row = conn.execute(
            text(f"select * from {table_name} where email = :email limit 1"),
            {"email": payload["email"]},
        ).mappings().first()

    return dict(row) if row else {"email": payload["email"]}
