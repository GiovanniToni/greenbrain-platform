from __future__ import annotations

from typing import Any, Dict

import json
import os
import urllib.error
import urllib.request

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.v1.auth import require_internal_admin
from app.core.config import settings
from app.db.session import get_db
from app.db.users import apply_cloud_password_sync
from app.services.customer_runtime_service import (
    create_provisioning_token,
    get_status,
    heartbeat_runtime,
    register_runtime,
)

router = APIRouter(prefix="/api/v1/customer-runtime", tags=["customer-runtime"])



class CreateProvisioningTokenPayload(BaseModel):
    customer_id: str
    tenant_code: str
    expires_days: int | None = 14


class RuntimeRegisterPayload(BaseModel):
    tenant_code: str
    installation_id: str
    tenant_name: str | None = None
    version: str | None = None
    installed_release_version: str | None = None
    local_backend_url: str | None = None
    public_backend_url: str | None = None
    tunnel_public_host: str | None = None
    connection_mode: str | None = "reverse-tunnel"
    data_mode: str | None = "local-db-via-tunnel"
    sync_enabled: bool | None = False
    sync_frequency_minutes: int | None = None
    runtime_health: str | None = None
    last_sync_status: str | None = None
    installation_label: str | None = "default"


class RuntimeHeartbeatPayload(BaseModel):
    tenant_code: str
    installation_id: str
    version: str | None = None
    runtime: Dict[str, Any] = Field(default_factory=dict)
    last_etl: str | None = None
    last_sync_status: str | None = None
    connection_mode: str | None = "reverse-tunnel"




def _runtime_env_value(name: str) -> str:
    return (os.environ.get(name) or "").strip()


def _central_base_url() -> str:
    explicit = _runtime_env_value("CENTRAL_AUTH_URL")
    if explicit:
        return explicit.rstrip("/")

    heartbeat_url = _runtime_env_value("HEARTBEAT_URL")
    suffix = "/api/v1/customer-runtime/heartbeat"
    if heartbeat_url.endswith(suffix):
        return heartbeat_url[: -len(suffix)].rstrip("/")

    return "https://www.greenbrain.it"


def _post_json(url: str, payload: dict, token: str | None = None, timeout: int = 12) -> tuple[int, dict]:
    data = json.dumps(payload).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "GreenBrainCustomerLocal/0.1.133 runtime-password-sync",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"

    req = urllib.request.Request(url, data=data, headers=headers, method="POST")

    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            body = response.read().decode("utf-8", "replace")
            parsed = json.loads(body) if body else {}
            return int(response.status), parsed
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        try:
            parsed = json.loads(body) if body else {}
        except Exception:
            parsed = {"detail": body}
        return int(exc.code), parsed


def _ensure_local_sync_request_allowed(request: Request) -> None:
    app_env = (settings.app_env or "").strip().lower()
    if app_env != "client-local":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="local_password_sync_only_available_in_client_local",
        )

    host = (request.headers.get("host") or "").split(":")[0].strip().lower()
    if host not in {"localhost", "127.0.0.1", "::1"}:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="local_password_sync_requires_localhost",
        )


@router.get("/health")
def customer_runtime_health():
    return {"status": "ok", "service": "customer-runtime"}



@router.post("/provisioning-token")
def create_provisioning_token_route(
    payload: CreateProvisioningTokenPayload,
    _: dict = Depends(require_internal_admin),
):
    try:
        return create_provisioning_token(
            customer_id=payload.customer_id,
            tenant_code=payload.tenant_code,
            expires_days=payload.expires_days or 14,
        )
    except RuntimeError as exc:
        msg = str(exc)
        if msg.endswith("_missing"):
            raise HTTPException(status_code=400, detail=msg)
        raise HTTPException(status_code=500, detail=f"runtime_token_create_failed: {exc}")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"runtime_token_create_failed: {exc}")


@router.post("/register")
def register_runtime_route(
    payload: RuntimeRegisterPayload,
    authorization: str | None = Header(default=None),
):
    try:
        token = None
        if authorization and authorization.lower().startswith('bearer '):
            token = authorization[7:].strip()
        return register_runtime(payload.model_dump(), provisioning_token=token)
    except RuntimeError as exc:
        msg = str(exc)
        if msg.endswith("_missing"):
            raise HTTPException(status_code=400, detail=msg)
        raise HTTPException(status_code=500, detail=f"runtime_register_failed: {exc}")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"runtime_register_failed: {exc}")


@router.post("/heartbeat")
def heartbeat_runtime_route(payload: RuntimeHeartbeatPayload):
    try:
        return heartbeat_runtime(payload.model_dump())
    except RuntimeError as exc:
        msg = str(exc)
        if msg.endswith("_missing"):
            raise HTTPException(status_code=400, detail=msg)
        raise HTTPException(status_code=500, detail=f"runtime_heartbeat_failed: {exc}")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"runtime_heartbeat_failed: {exc}")


@router.get("/status/{tenant_code}")
def runtime_status_route(tenant_code: str):
    try:
        return get_status(tenant_code)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"runtime_status_failed: {exc}")

@router.post("/password-sync/run-local")
def run_local_password_sync_route(
    request: Request,
    db: Session = Depends(get_db),
):
    """Trigger a best-effort local password sync from the cloud.

    This endpoint is intentionally trigger-only:
    - it accepts no password or hash from the browser;
    - it is enabled only in APP_ENV=client-local;
    - it only serves localhost/127.0.0.1 Host requests;
    - it pulls pending state from the cloud using the local runtime token.
    """

    _ensure_local_sync_request_allowed(request)

    tenant_code = _runtime_env_value("TENANT_CODE")
    installation_id = _runtime_env_value("INSTALLATION_ID")
    provisioning_token = _runtime_env_value("PROVISIONING_TOKEN")

    if not tenant_code:
        raise HTTPException(status_code=400, detail="tenant_code_missing")
    if not installation_id:
        raise HTTPException(status_code=400, detail="installation_id_missing")
    if not provisioning_token:
        raise HTTPException(status_code=400, detail="provisioning_token_missing")

    central = _central_base_url()
    pending_url = _runtime_env_value("PASSWORD_SYNC_PENDING_URL") or f"{central}/api/v1/customer-runtime/password-sync/pending"
    ack_url = _runtime_env_value("PASSWORD_SYNC_ACK_URL") or f"{central}/api/v1/customer-runtime/password-sync/ack"

    pending_status, pending = _post_json(
        pending_url,
        {"tenant_code": tenant_code, "installation_id": installation_id},
        token=provisioning_token,
    )

    if pending_status != 200:
        return {
            "status": "pending_failed",
            "pending_http_status": pending_status,
            "detail": pending.get("detail") or pending.get("message") or "pending_request_failed",
        }

    if not pending.get("has_pending"):
        return {
            "status": "no_pending",
            "tenant_code": tenant_code,
            "installation_id": installation_id,
        }

    user_id = (pending.get("user_id") or "").strip()
    email = (pending.get("email") or "").strip()
    hashed_password = (pending.get("hashed_password") or "").strip()
    password_version = pending.get("password_version")
    password_changed_at = pending.get("password_changed_at")

    if not user_id or not email or not hashed_password or not password_version:
        if user_id and password_version:
            _post_json(
                ack_url,
                {
                    "tenant_code": tenant_code,
                    "installation_id": installation_id,
                    "user_id": user_id,
                    "password_version": int(password_version or 0),
                    "status": "failed",
                    "error": "invalid_pending_payload",
                },
                token=provisioning_token,
            )
        return {"status": "failed", "error": "invalid_pending_payload"}

    try:
        updated = apply_cloud_password_sync(
            db,
            email=email,
            tenant_code=tenant_code,
            hashed_password=hashed_password,
            password_version=int(password_version),
            password_changed_at=password_changed_at,
            cloud_user_id=user_id,
            installation_id=installation_id,
        )
    except Exception as exc:
        _post_json(
            ack_url,
            {
                "tenant_code": tenant_code,
                "installation_id": installation_id,
                "user_id": user_id,
                "password_version": int(password_version),
                "status": "failed",
                "error": "local_update_failed",
            },
            token=provisioning_token,
        )
        return {
            "status": "failed",
            "error": "local_update_failed",
            "detail": str(exc),
        }

    ack_status, ack = _post_json(
        ack_url,
        {
            "tenant_code": tenant_code,
            "installation_id": installation_id,
            "user_id": user_id,
            "password_version": int(password_version),
            "status": "synced",
            "error": None,
        },
        token=provisioning_token,
    )

    return {
        "status": "synced",
        "tenant_code": tenant_code,
        "installation_id": installation_id,
        "email": email,
        "password_version": updated.get("password_version"),
        "password_last_sync_status": updated.get("password_last_sync_status"),
        "ack_http_status": ack_status,
        "ack_status": ack.get("status"),
    }

