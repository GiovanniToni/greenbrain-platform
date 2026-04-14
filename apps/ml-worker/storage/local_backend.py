from __future__ import annotations

from pathlib import Path

from .backend import build_local_target


class LocalStorageBackend:
    def upload_bytes(self, remote_path: str, content: bytes, content_type: str = "application/octet-stream") -> None:
        target = build_local_target(remote_path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)

    def download_bytes(self, remote_path: str) -> bytes:
        target = build_local_target(remote_path)
        return target.read_bytes()

    def exists(self, remote_path: str) -> bool:
        target = build_local_target(remote_path)
        return target.exists()

    def read(self, path: str) -> bytes:
        return self.download_bytes(path)

    def write(self, path: str, data: bytes) -> None:
        self.upload_bytes(path, data)

    def list(self, prefix: str = "") -> list[str]:
        from .backend import build_local_target, local_storage_root
        search_root = build_local_target(prefix) if prefix else local_storage_root()
        if not search_root.exists():
            return []
        base = local_storage_root()
        return sorted(
            str(p.relative_to(base))
            for p in search_root.rglob("*")
            if p.is_file()
        )

