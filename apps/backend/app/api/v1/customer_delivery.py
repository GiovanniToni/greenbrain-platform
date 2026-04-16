from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.services.customer_delivery_service import prepare_delivery_plan

router = APIRouter(prefix="/api/v1/customer-delivery", tags=["customer-delivery"])


class PrepareDeliveryPayload(BaseModel):
    customer_id: str


@router.get("/health")
def delivery_health():
    return {"status": "ok", "service": "customer-delivery"}


@router.post("/prepare")
def prepare_delivery_route(payload: PrepareDeliveryPayload):
    try:
        return prepare_delivery_plan(payload.customer_id)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_delivery_failed: {exc}")
