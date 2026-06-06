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
                CAST(NULLIF(:user_id, '') AS uuid),
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


def create_password_reset_token(
    db: Session,
    *,
    user_id: str,
    email: str,
    token_hash: str,
    source: str = "self_service",
    expires_at: str,
    created_by_user_id: str | None = None,
    requested_ip: str | None = None,
    requested_user_agent: str | None = None,
    details: dict[str, Any] | None = None,
) -> dict:
    clean_email = email.lower().strip()
    if not user_id:
        raise ValueError("user_id_required")
    if not clean_email:
        raise ValueError("email_required")
    if not token_hash:
        raise ValueError("token_hash_required")
    if source not in {"self_service", "admin", "dev"}:
        raise ValueError("invalid_reset_token_source")
    if not expires_at:
        raise ValueError("expires_at_required")

    # Only one active reset token per user/email. Old active tokens are revoked
    # before creating the new one. Raw tokens are never stored here.
    db.execute(
        text("""
            UPDATE public.greenbrain_user_password_reset_tokens
            SET
              status = 'revoked',
              revoked_at = now(),
              details = details || CAST(:revoke_details AS jsonb)
            WHERE status = 'active'
              AND used_at IS NULL
              AND revoked_at IS NULL
              AND (
                user_id = CAST(:user_id AS uuid)
                OR lower(email) = lower(:email)
              )
        """),
        {
            "user_id": user_id,
            "email": clean_email,
            "revoke_details": json.dumps(
                {
                    "reason": "superseded_by_new_reset_token",
                    "new_source": source,
                },
                ensure_ascii=False,
            ),
        },
    )

    row = db.execute(
        text("""
            INSERT INTO public.greenbrain_user_password_reset_tokens
              (
                user_id,
                email,
                token_hash,
                source,
                status,
                expires_at,
                created_by_user_id,
                requested_ip,
                requested_user_agent,
                details
              )
            VALUES
              (
                CAST(:user_id AS uuid),
                :email,
                :token_hash,
                :source,
                'active',
                CAST(:expires_at AS timestamptz),
                CAST(NULLIF(:created_by_user_id, '') AS uuid),
                :requested_ip,
                :requested_user_agent,
                CAST(:details AS jsonb)
              )
            RETURNING *
        """),
        {
            "user_id": user_id,
            "email": clean_email,
            "token_hash": token_hash,
            "source": source,
            "expires_at": expires_at,
            "created_by_user_id": created_by_user_id or "",
            "requested_ip": requested_ip,
            "requested_user_agent": requested_user_agent,
            "details": json.dumps(details or {}, ensure_ascii=False),
        },
    ).mappings().first()

    if not row:
        raise ValueError("password_reset_token_not_created")

    db.commit()
    return dict(row)


def get_active_password_reset_token_by_hash(db: Session, token_hash: str) -> Optional[dict]:
    if not token_hash:
        return None

    row = db.execute(
        text("""
            SELECT
              t.*,
              u.email AS user_email,
              u.is_active AS user_is_active,
              u.hashed_password AS user_hashed_password,
              u.tenant_code AS user_tenant_code
            FROM public.greenbrain_user_password_reset_tokens t
            LEFT JOIN public.greenbrain_users u
              ON u.id = t.user_id
            WHERE t.token_hash = :token_hash
              AND t.status = 'active'
              AND t.used_at IS NULL
              AND t.revoked_at IS NULL
              AND t.expires_at > now()
            LIMIT 1
        """),
        {"token_hash": token_hash},
    ).mappings().first()

    return dict(row) if row else None


def mark_password_reset_token_used(
    db: Session,
    *,
    token_id: str,
    details: dict[str, Any] | None = None,
) -> dict:
    if not token_id:
        raise ValueError("token_id_required")

    row = db.execute(
        text("""
            UPDATE public.greenbrain_user_password_reset_tokens
            SET
              status = 'used',
              used_at = now(),
              details = details || CAST(:details AS jsonb)
            WHERE id = CAST(:token_id AS uuid)
              AND status = 'active'
              AND used_at IS NULL
              AND revoked_at IS NULL
              AND expires_at > now()
            RETURNING *
        """),
        {
            "token_id": token_id,
            "details": json.dumps(details or {}, ensure_ascii=False),
        },
    ).mappings().first()

    if not row:
        raise ValueError("password_reset_token_not_active")

    db.commit()
    return dict(row)


def expire_password_reset_tokens(db: Session) -> int:
    result = db.execute(
        text("""
            UPDATE public.greenbrain_user_password_reset_tokens
            SET status = 'expired'
            WHERE status = 'active'
              AND used_at IS NULL
              AND revoked_at IS NULL
              AND expires_at <= now()
        """)
    )
    db.commit()
    return int(result.rowcount or 0)


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
              password_changed_by = CAST(NULLIF(:changed_by_user_id, '') AS uuid),
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
            "changed_by_user_id": changed_by_user_id or "",
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
            "changed_by_user_id": changed_by_user_id or "",
            "sync_status": updated.get("password_last_sync_status"),
        },
    )
    db.commit()
    return updated

def ensure_password_sync_schema(db: Session) -> None:
    db.execute(text("""
        ALTER TABLE public.greenbrain_users
          ADD COLUMN IF NOT EXISTS password_changed_at timestamptz,
          ADD COLUMN IF NOT EXISTS password_changed_by uuid,
          ADD COLUMN IF NOT EXISTS password_change_source text NOT NULL DEFAULT 'initial',
          ADD COLUMN IF NOT EXISTS password_version integer NOT NULL DEFAULT 1,
          ADD COLUMN IF NOT EXISTS password_sync_required_at timestamptz,
          ADD COLUMN IF NOT EXISTS password_last_synced_at timestamptz,
          ADD COLUMN IF NOT EXISTS password_last_sync_status text NOT NULL DEFAULT 'not_required',
          ADD COLUMN IF NOT EXISTS password_last_sync_error text,
          ADD COLUMN IF NOT EXISTS password_last_sync_attempt_at timestamptz
    """))

    db.execute(text("""
        CREATE TABLE IF NOT EXISTS public.greenbrain_user_password_events (
          id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id uuid REFERENCES public.greenbrain_users(id) ON DELETE SET NULL,
          email text NOT NULL,
          tenant_code text,
          event_type text NOT NULL,
          source text NOT NULL DEFAULT 'local',
          status text NOT NULL DEFAULT 'ok',
          password_version integer,
          occurred_at timestamptz NOT NULL DEFAULT now(),
          details jsonb NOT NULL DEFAULT '{}'::jsonb
        )
    """))


def apply_cloud_password_sync(
    db: Session,
    *,
    email: str,
    tenant_code: str,
    hashed_password: str,
    password_version: int,
    password_changed_at: str | None,
    cloud_user_id: str | None,
    installation_id: str | None,
) -> dict:
    clean_email = email.lower().strip()
    clean_tenant = (tenant_code or "").strip()

    if not clean_email:
        raise ValueError("email_missing")
    if not clean_tenant:
        raise ValueError("tenant_code_missing")
    if not hashed_password:
        raise ValueError("hashed_password_missing")
    if not password_version:
        raise ValueError("password_version_missing")

    ensure_password_sync_schema(db)

    row = db.execute(
        text("""
            UPDATE public.greenbrain_users
            SET
              hashed_password = :hashed_password,
              password_changed_at = COALESCE(NULLIF(:password_changed_at, '')::timestamptz, now()),
              password_change_source = 'cloud_sync',
              password_version = :password_version,
              password_last_synced_at = now(),
              password_last_sync_attempt_at = now(),
              password_last_sync_status = 'synced',
              password_last_sync_error = NULL
            WHERE lower(email) = lower(:email)
              AND COALESCE(tenant_code, '') = :tenant_code
            RETURNING id, email, tenant_code, password_version, password_last_synced_at, password_last_sync_status
        """),
        {
            "hashed_password": hashed_password,
            "password_changed_at": password_changed_at or "",
            "password_version": int(password_version),
            "email": clean_email,
            "tenant_code": clean_tenant,
        },
    ).mappings().first()

    if not row:
        db.rollback()
        raise ValueError("local_user_not_found_or_not_updated")

    updated = dict(row)

    record_password_event(
        db,
        user_id=str(updated["id"]),
        email=updated["email"],
        tenant_code=updated.get("tenant_code"),
        event_type="password_synced_from_cloud",
        source="local_runtime",
        status="ok",
        password_version=updated.get("password_version"),
        details={
            "cloud_user_id": cloud_user_id or "",
            "installation_id": installation_id or "",
            "trigger": "local_api",
        },
    )

    db.commit()
    return updated
