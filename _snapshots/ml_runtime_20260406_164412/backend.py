from __future__ import annotations

import os
from pathlib import Path
from typing import Protocol, runtime_checkable


@runtime_checkable
class StorageBackend(Protocol):
    def upload_bytes(self, remote_path: str, content: bytes, content_type: str = "application/octet-stream") -> None:
        ...

    def download_bytes(self, remote_path: str) -> bytes:
        ...

    def exists(self, remote_path: str) -> bool:
        ...

    def read(self, path: str) -> bytes:
        ...

    def write(self, path: str, data: bytes) -> None:
        ...

    def list(self, prefix: str = "") -> list[str]:
        ...


def storage_backend_name() -> str:
    return os.getenv("STORAGE_BACKEND", "supabase").strip().lower()


def local_storage_root() -> Path:
    return Path(os.getenv("LOCAL_STORAGE_ROOT", "/opt/greenbrain/storage")).resolve()


def normalize_remote_path(remote_path: str) -> str:
    return remote_path.lstrip("/")


def build_local_target(remote_path: str) -> Path:
    return local_storage_root() / normalize_remote_path(remote_path)


def get_storage_backend() -> StorageBackend:
    """Backward-compatible alias for storage.factory.get_storage()."""
    from .factory import get_storage
    return get_storage()
