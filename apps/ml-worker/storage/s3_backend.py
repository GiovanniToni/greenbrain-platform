from __future__ import annotations

import io
import os

import boto3
from botocore.exceptions import ClientError


class S3StorageBackend:
    def __init__(self) -> None:
        endpoint = os.environ["S3_ENDPOINT"]
        region = os.getenv("S3_REGION", "us-east-1")
        access_key = os.environ["S3_ACCESS_KEY"]
        secret_key = os.environ["S3_SECRET_KEY"]
        self.bucket = os.environ["S3_BUCKET"]

        self.client = boto3.client(
            "s3",
            endpoint_url=endpoint,
            region_name=region,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
        )

    def upload_bytes(self, remote_path: str, content: bytes, content_type: str = "application/octet-stream") -> None:
        self.client.upload_fileobj(
            Fileobj=io.BytesIO(content),
            Bucket=self.bucket,
            Key=remote_path,
            ExtraArgs={"ContentType": content_type},
        )

    def download_bytes(self, remote_path: str) -> bytes:
        buf = io.BytesIO()
        self.client.download_fileobj(self.bucket, remote_path, buf)
        return buf.getvalue()

    def exists(self, remote_path: str) -> bool:
        try:
            self.client.head_object(Bucket=self.bucket, Key=remote_path)
            return True
        except ClientError:
            return False

    def read(self, path: str) -> bytes:
        return self.download_bytes(path)

    def write(self, path: str, data: bytes) -> None:
        self.upload_bytes(path, data)

    def list(self, prefix: str = "") -> list[str]:
        paginator = self.client.get_paginator("list_objects_v2")
        pages = paginator.paginate(Bucket=self.bucket, Prefix=prefix.lstrip("/"))
        return [obj["Key"] for page in pages for obj in page.get("Contents", [])]

