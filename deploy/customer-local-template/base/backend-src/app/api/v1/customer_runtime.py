from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field

from app.api.v1.auth import require_admin
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


@router.get("/health")
def customer_runtime_health():
    return {"status": "ok", "service": "customer-runtime"}



@router.post("/provisioning-token")
def create_provisioning_token_route(
    payload: CreateProvisioningTokenPayload,
    _: dict = Depends(require_admin),
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
