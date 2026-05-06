from __future__ import annotations

from typing import Protocol, runtime_checkable


@runtime_checkable
class StorageInterface(Protocol):
    """
    Minimal storage contract used by all GreenBrain ML pipeline scripts.

    All paths are forward-slash relative strings (no leading slash).
    Backends map them onto their native addressing scheme.

    Environment variables (read by factory.py):
        STORAGE_BACKEND   local | s3 | supabase   (default: supabase)
        STORAGE_BASE_PATH path for local backend   (default: LOCAL_STORAGE_ROOT or
                                                    /opt/greenbrain/storage)
    """

    def read(self, path: str) -> bytes:
        """Return raw bytes at *path*. Raise FileNotFoundError / equivalent if absent."""
        ...

    def write(self, path: str, data: bytes) -> None:
        """Persist *data* at *path*, creating intermediate directories as needed."""
        ...

    def exists(self, path: str) -> bool:
        """Return True if *path* is present in the backend."""
        ...

    def list(self, prefix: str = "") -> list[str]:
        """
        Return all keys whose path starts with *prefix*.
        Returns an empty list when nothing matches.
        """
        ...
