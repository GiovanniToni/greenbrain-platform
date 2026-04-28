from __future__ import annotations

import uuid
from typing import Optional

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
