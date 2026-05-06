from __future__ import annotations

import io
import os

def _require(name: str, *fallbacks: str) -> str:
    for key in (name, *fallbacks):
        v = os.environ.get(key)
        if v:
            return v
    raise EnvironmentError(f"Missing env var: {name} (also tried: {list(fallbacks)})")


class S3Storage:
    """
    StorageInterface backed by S3-compatible object storage.

    Reads credentials from env vars with DO Spaces fallback aliases:

        S3_ENDPOINT  (or auto-built from DO_SPACES_REGION)
        S3_REGION    / DO_SPACES_REGION
        S3_ACCESS_KEY / DO_SPACES_KEY
        S3_SECRET_KEY / DO_SPACES_SECRET
        S3_BUCKET    / DO_SPACES_BUCKET
    """

    def __init__(self) -> None:
        region = os.getenv("S3_REGION") or _require("DO_SPACES_REGION")
        endpoint = (
            os.getenv("S3_ENDPOINT")
            or os.getenv("DO_SPACES_ENDPOINT")
            or f"https://{region}.digitaloceanspaces.com"
        )
        access_key = _require("S3_ACCESS_KEY", "DO_SPACES_KEY")
        secret_key = _require("S3_SECRET_KEY", "DO_SPACES_SECRET")
        self._bucket = _require("S3_BUCKET", "DO_SPACES_BUCKET")

        import boto3
        from botocore.exceptions import ClientError  # noqa: F401
        self._client = boto3.client(
            "s3",
            endpoint_url=endpoint,
            region_name=region,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
        )

    # ── StorageInterface ──────────────────────────────────────────────────────

    def read(self, path: str) -> bytes:
        buf = io.BytesIO()
        try:
            self._client.download_fileobj(self._bucket, path.lstrip("/"), buf)
        except Exception as exc:
            from botocore.exceptions import ClientError
            code = exc.response["Error"]["Code"]
            if code in ("404", "NoSuchKey"):
                raise FileNotFoundError(f"S3Storage: not found: {path}") from exc
            raise
        return buf.getvalue()

    def write(
        self, path: str, data: bytes, content_type: str = "application/octet-stream"
    ) -> None:
        self._client.upload_fileobj(
            Fileobj=io.BytesIO(data),
            Bucket=self._bucket,
            Key=path.lstrip("/"),
            ExtraArgs={"ContentType": content_type},
        )

    def exists(self, path: str) -> bool:
        try:
            self._client.head_object(Bucket=self._bucket, Key=path.lstrip("/"))
            return True
        except Exception:
            return False

    def list(self, prefix: str = "") -> list[str]:
        paginator = self._client.get_paginator("list_objects_v2")
        pages = paginator.paginate(Bucket=self._bucket, Prefix=prefix.lstrip("/"))
        return [obj["Key"] for page in pages for obj in page.get("Contents", [])]

    # ── backward-compat aliases ───────────────────────────────────────────────

    def upload_bytes(
        self, remote_path: str, content: bytes, content_type: str = "application/octet-stream"
    ) -> None:
        self.write(remote_path, content, content_type)

    def download_bytes(self, remote_path: str) -> bytes:
        return self.read(remote_path)
