from __future__ import annotations

import os

from .storage_interface import StorageInterface


def get_storage(backend: str | None = None) -> StorageInterface:
    """
    Return a StorageInterface instance selected by *backend* or the
    STORAGE_BACKEND environment variable.

    Values:
        local    — local filesystem (STORAGE_BASE_PATH or LOCAL_STORAGE_ROOT)
        s3       — S3-compatible object storage (incl. DO Spaces)
        supabase — Supabase Storage (default; requires SUPABASE_URL + key)
    """
    name = (backend or os.getenv("STORAGE_BACKEND", "supabase")).strip().lower()

    if name == "local":
        from .local_storage import LocalStorage
        return LocalStorage()

    if name in ("s3", "do", "spaces"):
        from .s3_storage import S3Storage
        return S3Storage()

    if name == "supabase":
        from .supabase_backend import SupabaseStorageBackend
        return SupabaseStorageBackend()

    raise ValueError(
        f"Unknown STORAGE_BACKEND={name!r}. Valid values: local, s3, supabase"
    )
