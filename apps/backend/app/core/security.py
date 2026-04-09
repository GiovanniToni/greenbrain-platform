from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt
from passlib.context import CryptContext

from app.core.config import settings

logger = logging.getLogger(__name__)

ALGORITHM = "HS256"

_pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    return _pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return _pwd_context.verify(plain, hashed)


def create_access_token(subject: str) -> str:
    if settings.jwt_secret == "CHANGE_ME_dev_only_not_for_production":
        logger.warning(
            "JWT_SECRET is the default dev value. "
            "Set a strong JWT_SECRET in production."
        )
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.jwt_expire_minutes
    )
    payload = {"sub": subject, "exp": expire}
    return jwt.encode(payload, settings.jwt_secret, algorithm=ALGORITHM)


def decode_token(token: str) -> str:
    """Decode JWT and return the subject (user email). Raises JWTError on failure."""
    payload = jwt.decode(token, settings.jwt_secret, algorithms=[ALGORITHM])
    sub: str | None = payload.get("sub")
    if not sub:
        raise JWTError("Missing subject in token")
    return sub
