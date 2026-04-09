from __future__ import annotations

import os
from pathlib import Path


def _default_base() -> Path:
    p = os.getenv("STORAGE_BASE_PATH") or os.getenv("LOCAL_STORAGE_ROOT", "/opt/greenbrain/storage")
    return Path(p).expanduser().resolve()


class LocalStorage:
    """
    StorageInterface backed by the local filesystem.

    All paths are resolved relative to *base_path* (or STORAGE_BASE_PATH /
    LOCAL_STORAGE_ROOT env var).  No network I/O.
    """

    def __init__(self, base_path: str | Path | None = None) -> None:
        self._base: Path = Path(base_path).expanduser().resolve() if base_path else _default_base()

    # ── StorageInterface ──────────────────────────────────────────────────────

    def read(self, path: str) -> bytes:
        target = self._resolve(path)
        if not target.exists():
            raise FileNotFoundError(f"LocalStorage: not found: {target}")
        return target.read_bytes()

    def write(self, path: str, data: bytes) -> None:
        target = self._resolve(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)

    def exists(self, path: str) -> bool:
        return self._resolve(path).exists()

    def list(self, prefix: str = "") -> list[str]:
        search_root = self._resolve(prefix) if prefix else self._base
        if not search_root.exists():
            return []
        return sorted(
            str(p.relative_to(self._base))
            for p in search_root.rglob("*")
            if p.is_file()
        )

    # ── backward-compat aliases (used by legacy callers) ─────────────────────

    def upload_bytes(
        self, remote_path: str, content: bytes, content_type: str = "application/octet-stream"
    ) -> None:
        self.write(remote_path, content)

    def download_bytes(self, remote_path: str) -> bytes:
        return self.read(remote_path)

    # ── helpers ───────────────────────────────────────────────────────────────

    def _resolve(self, path: str) -> Path:
        return self._base / path.lstrip("/")

    @property
    def base_path(self) -> Path:
        return self._base
