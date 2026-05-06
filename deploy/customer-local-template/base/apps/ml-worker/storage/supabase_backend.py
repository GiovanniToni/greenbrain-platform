from __future__ import annotations

import os

from supabase import create_client


class SupabaseStorageBackend:
    def __init__(self) -> None:
        self.url = os.environ["SUPABASE_URL"]
        self.key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
        self.bucket = os.getenv("SUPABASE_BUCKET", "ml-snapshots")
        self.client = create_client(self.url, self.key)

    def upload_bytes(self, remote_path: str, content: bytes, content_type: str = "application/octet-stream") -> None:
        self.client.storage.from_(self.bucket).upload(
            path=remote_path,
            file=content,
            file_options={"content-type": content_type, "upsert": "true"},
        )

    def download_bytes(self, remote_path: str) -> bytes:
        return self.client.storage.from_(self.bucket).download(remote_path)

    def exists(self, remote_path: str) -> bool:
        try:
            parent = remote_path.rsplit("/", 1)[0] if "/" in remote_path else ""
            name = remote_path.rsplit("/", 1)[-1]
            rows = self.client.storage.from_(self.bucket).list(path=parent)
            return any((row.get("name") == name) for row in rows)
        except Exception:
            return False

    def read(self, path: str) -> bytes:
        return self.download_bytes(path)

    def write(self, path: str, data: bytes) -> None:
        self.upload_bytes(path, data)

    def list(self, prefix: str = "") -> list[str]:
        try:
            rows = self.client.storage.from_(self.bucket).list(path=prefix.rstrip("/"))
            return [
                (prefix.rstrip("/") + "/" + r["name"]).lstrip("/")
                for r in (rows or [])
                if r.get("name")
            ]
        except Exception:
            return []

