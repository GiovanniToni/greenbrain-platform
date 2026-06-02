from __future__ import annotations

import json

import uuid
from typing import Any, Optional

from sqlalchemy import text
from sqlalchemy.orm import Session


def get_user_by_email(db: Session, email: str) -> Optional[dict]:
    row = db.execute(
        text("SELECT * FROM greenbrain_users WHERE email = :email"),
        {"email": email.lower().strip()},
    ).mappings().first()
    return dict(row) if row else None


def get_user_by_id(db: Session, user_id: str) -> Optional[dict]:
    row = db.execute(
        text("SELECT * FROM greenbrain_users WHERE id = CAST(:id AS uuid)"),
        {"id": user_id},
    ).mappings().first()
    return dict(row) if row else None


def count_users(db: Session) -> int:
    result = db.execute(text("SELECT COUNT(*) FROM greenbrain_users")).scalar()
    return int(result or 0)


def create_user(
    db: Session,
    email: str,
    hashed_password: str,
    full_name: Optional[str] = None,
    is_admin: bool = False,
    tenant_code: Optional[str] = None,
    home_host: Optional[str] = None,
    home_path: Optional[str] = None,
    user_role: Optional[str] = None,
) -> dict:
    user_id = str(uuid.uuid4())
    db.execute(
        text("""
            INSERT INTO greenbrain_users
                (id, email, hashed_password, full_name, is_admin,
                 tenant_code, home_host, home_path, user_role)
            VALUES
                (CAST(:id AS uuid), :email, :hashed_password, :full_name, :is_admin,
                 :tenant_code, :home_host, :home_path, :user_role)
        """),
        {
            "id": user_id,
            "email": email.lower().strip(),
            "hashed_password": hashed_password,
            "full_name": full_name,
            "is_admin": is_admin,
            "tenant_code": tenant_code or ("greenbrain" if is_admin else None),
            "home_host": home_host or "www.greenbrain.it",
            "home_path": home_path or ("/ops" if is_admin else "/account"),
            "user_role": user_role or ("greenbrain_admin" if is_admin else "customer_admin"),
        },
    )
    db.commit()
    return get_user_by_id(db, user_id)


def update_last_login(db: Session, user_id: str) -> None:
    db.execute(
        text("UPDATE greenbrain_users SET last_login_at = now() WHERE id = CAST(:id AS uuid)"),
        {"id": user_id},
    )
    db.commit()


def create_admin_user(
    db: Session,
    email: str,
    hashed_password: str,
    full_name: Optional[str] = None,
) -> dict:
    user_id = str(uuid.uuid4())
    db.execute(
        text("""
            INSERT INTO greenbrain_users
                (id, email, hashed_password, full_name, is_admin,
                 tenant_code, home_host, home_path, user_role, is_active)
            VALUES
                (CAST(:id AS uuid), :email, :hashed_password, :full_name, true,
                 'greenbrain', 'www.greenbrain.it', '/ops', 'greenbrain_admin', true)
        """),
        {
            "id": user_id,
            "email": email.lower().strip(),
            "hashed_password": hashed_password,
            "full_name": full_name,
        },
    )
    db.commit()
    return get_user_by_id(db, user_id)


def record_password_event(
    db: Session,
    *,
    user_id: str | None,
    email: str,
    tenant_code: str | None,
    event_type: str,
    source: str = "cloud",
    status: str = "ok",
    password_version: int | None = None,
    details: dict[str, Any] | None = None,
) -> None:
    db.execute(
        text("""
            INSERT INTO greenbrain_user_password_events
              (user_id, email, tenant_code, event_type, source, status, password_version, details)
            VALUES
              (
                CASE WHEN :user_id IS NULL THEN NULL ELSE CAST(:user_id AS uuid) END,
                :email,
                :tenant_code,
                :event_type,
                :source,
                :status,
                :password_version,
                CAST(:details AS jsonb)
              )
        """),
        {
            "user_id": user_id,
            "email": email.lower().strip(),
            "tenant_code": tenant_code,
            "event_type": event_type,
            "source": source,
            "status": status,
            "password_version": password_version,
            "details": json.dumps(details or {}, ensure_ascii=False),
        },
    )


def update_user_password_hash(
    db: Session,
    *,
    user_id: str,
    hashed_password: str,
    changed_by_user_id: str | None = None,
    source: str = "cloud",
) -> dict:
    row = db.execute(
        text("""
            UPDATE greenbrain_users
            SET
              hashed_password = :hashed_password,
              password_changed_at = now(),
              password_changed_by = CASE
                WHEN :changed_by_user_id IS NULL THEN NULL
                ELSE CAST(:changed_by_user_id AS uuid)
              END,
              password_change_source = :source,
              password_version = COALESCE(password_version, 0) + 1,
              password_sync_required_at = CASE
                WHEN tenant_code IS NULL OR tenant_code = 'greenbrain' THEN password_sync_required_at
                ELSE now()
              END,
              password_last_sync_status = CASE
                WHEN tenant_code IS NULL OR tenant_code = 'greenbrain' THEN 'not_required'
                ELSE 'pending'
              END,
              password_last_sync_error = NULL
            WHERE id = CAST(:user_id AS uuid)
            RETURNING *
        """),
        {
            "user_id": user_id,
            "hashed_password": hashed_password,
            "changed_by_user_id": changed_by_user_id,
            "source": source,
        },
    ).mappings().first()

    if not row:
        raise ValueError("user_not_found")

    updated = dict(row)
    record_password_event(
        db,
        user_id=str(updated["id"]),
        email=updated["email"],
        tenant_code=updated.get("tenant_code"),
        event_type="password_changed",
        source=source,
        status="ok",
        password_version=updated.get("password_version"),
        details={
            "changed_by_user_id": changed_by_user_id,
            "sync_status": updated.get("password_last_sync_status"),
        },
    )
    db.commit()
    return updated

