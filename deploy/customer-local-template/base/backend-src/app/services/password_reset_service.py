from __future__ import annotations

import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any
from urllib.parse import quote

from sqlalchemy.orm import Session

from app.core.security import hash_password, verify_password
from app.db.users import (
    create_password_reset_token,
    expire_password_reset_tokens,
    get_active_password_reset_token_by_hash,
    get_user_by_email,
    mark_password_reset_token_used,
    update_user_password_hash,
)


DEFAULT_RESET_EXPIRES_MINUTES = 60


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(microsecond=0)


def hash_reset_token(raw_token: str) -> str:
    token = (raw_token or "").strip()
    if not token:
        raise ValueError("reset_token_required")
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def generate_password_reset_token() -> str:
    return "gbr_" + secrets.token_urlsafe(32)


def build_password_reset_url(raw_token: str, frontend_base_url: str | None = None) -> str | None:
    base = (frontend_base_url or "").strip().rstrip("/")
    if not base:
        return None
    return f"{base}/reset-password?token={quote(raw_token)}"


def create_password_reset_for_email(
    db: Session,
    *,
    email: str,
    source: str = "self_service",
    frontend_base_url: str | None = None,
    created_by_user_id: str | None = None,
    requested_ip: str | None = None,
    requested_user_agent: str | None = None,
    expires_minutes: int = DEFAULT_RESET_EXPIRES_MINUTES,
) -> dict[str, Any]:
    clean_email = (email or "").lower().strip()
    if not clean_email:
        raise ValueError("email_required")
    if source not in {"self_service", "admin", "dev"}:
        raise ValueError("invalid_reset_token_source")
    if expires_minutes <= 0:
        raise ValueError("invalid_reset_token_expiry")

    # Do not reveal whether an email exists to self-service callers.
    user = get_user_by_email(db, clean_email)
    if not user:
        return {
            "status": "not_found",
            "email": clean_email,
            "token_created": False,
            "reset_url": None,
            "expires_at": None,
        }

    expire_password_reset_tokens(db)

    raw_token = generate_password_reset_token()
    token_hash = hash_reset_token(raw_token)
    expires_at = (_now() + timedelta(minutes=expires_minutes)).isoformat()

    row = create_password_reset_token(
        db,
        user_id=str(user["id"]),
        email=user["email"],
        token_hash=token_hash,
        source=source,
        expires_at=expires_at,
        created_by_user_id=created_by_user_id,
        requested_ip=requested_ip,
        requested_user_agent=requested_user_agent,
        details={
            "created_for": "password_reset",
            "expires_minutes": expires_minutes,
        },
    )

    return {
        "status": "created",
        "email": user["email"],
        "user_id": str(user["id"]),
        "token": raw_token,
        "token_hint": raw_token[-6:],
        "reset_url": build_password_reset_url(raw_token, frontend_base_url),
        "expires_at": row.get("expires_at"),
        "row": row,
    }


def reset_password_with_token(
    db: Session,
    *,
    raw_token: str,
    new_password: str,
    changed_by_user_id: str | None = None,
) -> dict[str, Any]:
    password = new_password or ""
    if len(password) < 8:
        raise ValueError("new_password_too_short")

    token_hash = hash_reset_token(raw_token)
    token_row = get_active_password_reset_token_by_hash(db, token_hash)
    if not token_row:
        raise ValueError("password_reset_token_invalid_or_expired")

    user_id = str(token_row.get("user_id") or "")
    if not user_id:
        raise ValueError("password_reset_token_user_missing")

    if token_row.get("user_is_active") is False:
        raise ValueError("password_reset_user_inactive")

    current_hash = token_row.get("user_hashed_password")
    if current_hash and verify_password(password, current_hash):
        raise ValueError("new_password_same_as_current")

    updated = update_user_password_hash(
        db,
        user_id=user_id,
        hashed_password=hash_password(password),
        changed_by_user_id=changed_by_user_id or user_id,
        source="password_reset",
    )

    used = mark_password_reset_token_used(
        db,
        token_id=str(token_row["id"]),
        details={
            "used_for": "password_reset",
            "password_version": updated.get("password_version"),
        },
    )

    return {
        "status": "reset",
        "email": updated["email"],
        "password_changed_at": updated.get("password_changed_at"),
        "password_version": updated.get("password_version"),
        "password_last_sync_status": updated.get("password_last_sync_status"),
        "password_sync_required_at": updated.get("password_sync_required_at"),
        "token_used_at": used.get("used_at"),
    }
