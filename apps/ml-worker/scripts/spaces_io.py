"""
spaces_io — thin adapter over the StorageInterface factory.

Previously used direct boto3 / DO Spaces calls.  Now all I/O is routed through
storage.factory.get_storage() so that STORAGE_BACKEND=local|s3|supabase controls
the underlying implementation.  Call signatures are unchanged.
"""
from __future__ import annotations

import os
from pathlib import Path

from storage.factory import get_storage


def upload_file(local_path: str, key: str) -> None:
    """Upload *local_path* to *key* on the configured storage backend."""
    storage = get_storage()
    storage.write(key, Path(local_path).read_bytes())


def download_file(key: str, local_path: str) -> None:
    """Download *key* from the configured storage backend to *local_path*."""
    storage = get_storage()
    data = storage.read(key)
    os.makedirs(os.path.dirname(os.path.abspath(local_path)), exist_ok=True)
    Path(local_path).write_bytes(data)


def head(key: str) -> bool:
    """Return True if *key* exists in the configured storage backend."""
    storage = get_storage()
    return storage.exists(key)
