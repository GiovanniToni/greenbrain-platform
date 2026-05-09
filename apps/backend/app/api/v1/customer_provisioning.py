from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.api.v1.auth import require_internal_admin
from app.services.customer_provisioning_service import assign_release

router = APIRouter(prefix="/api/v1/customer-provisioning", tags=["customer-provisioning"])


class AssignReleasePayload(BaseModel):
    customer_id: str
    assigned_release_version: str


@router.get("/health")
def provisioning_health():
    return {"status": "ok", "service": "customer-provisioning"}


@router.post("/assign-release")
def assign_release_route(
    payload: AssignReleasePayload,
    _: dict = Depends(require_internal_admin),
):
    try:
        result = assign_release(
            customer_id=payload.customer_id,
            assigned_release_version=payload.assigned_release_version,
        )
        return {
            "status": "assigned",
            "customer_id": payload.customer_id,
            "assigned_release_version": payload.assigned_release_version,
            "customer": result["customer"],
            "delivery": result["delivery"],
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_provisioning_failed: {exc}")
