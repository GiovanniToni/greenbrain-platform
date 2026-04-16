from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter(prefix="/api/v1/customer-provisioning", tags=["customer-provisioning"])


class AssignReleasePayload(BaseModel):
    customer_id: str
    assigned_release_version: str


@router.get("/health")
def provisioning_health():
    return {"status": "ok", "service": "customer-provisioning"}


@router.post("/assign-release")
def assign_release(payload: AssignReleasePayload):
    try:
        return {
            "status": "stub_assigned",
            "customer_id": payload.customer_id,
            "assigned_release_version": payload.assigned_release_version,
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_provisioning_failed: {exc}")
