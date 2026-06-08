from __future__ import annotations

from cryptography.fernet import Fernet, InvalidToken

from app.core.config import settings


class SecretCryptoNotConfigured(RuntimeError):
    """Raised when credential encryption is requested without a configured key."""


class SecretCryptoError(RuntimeError):
    """Raised when encryption/decryption fails."""


def _get_fernet() -> Fernet:
    key = (settings.source_db_secret_key or "").strip()
    if not key:
        raise SecretCryptoNotConfigured("source_db_secret_key_not_configured")
    try:
        return Fernet(key.encode("utf-8"))
    except Exception as exc:
        raise SecretCryptoNotConfigured("source_db_secret_key_invalid") from exc


def encrypt_secret(plain_text: str) -> str:
    value = plain_text or ""
    if not value:
        raise SecretCryptoError("secret_value_empty")
    try:
        return _get_fernet().encrypt(value.encode("utf-8")).decode("utf-8")
    except SecretCryptoNotConfigured:
        raise
    except Exception as exc:
        raise SecretCryptoError("secret_encrypt_failed") from exc


def decrypt_secret(cipher_text: str) -> str:
    value = cipher_text or ""
    if not value:
        raise SecretCryptoError("cipher_text_empty")
    try:
        return _get_fernet().decrypt(value.encode("utf-8")).decode("utf-8")
    except SecretCryptoNotConfigured:
        raise
    except InvalidToken as exc:
        raise SecretCryptoError("secret_decrypt_invalid_token") from exc
    except Exception as exc:
        raise SecretCryptoError("secret_decrypt_failed") from exc
