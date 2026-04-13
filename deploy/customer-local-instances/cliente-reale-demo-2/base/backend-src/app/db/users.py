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
) -> dict:
    user_id = str(uuid.uuid4())
    db.execute(
        text("""
            INSERT INTO greenbrain_users
                (id, email, hashed_password, full_name, is_admin)
            VALUES
                (CAST(:id AS uuid), :email, :hashed_password, :full_name, :is_admin)
        """),
        {
            "id": user_id,
            "email": email.lower().strip(),
            "hashed_password": hashed_password,
            "full_name": full_name,
            "is_admin": is_admin,
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
