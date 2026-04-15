from __future__ import annotations

from fastapi import APIRouter

from app.schemas.customer_ops import CustomerCompanyCreate
from app.services.customer_ops_service import list_customers_stub

router = APIRouter(prefix="/api/v1/customer-ops", tags=["customer-ops"])


@router.get("/health")
def customer_ops_health():
    return {"status": "ok", "service": "customer-ops"}


@router.get("/customers")
def list_customers():
    return {"items": list_customers_stub()}


@router.post("/customers")
def create_customer(payload: CustomerCompanyCreate):
    return {
        "status": "stub_created",
        "payload": payload.model_dump(),
    }
