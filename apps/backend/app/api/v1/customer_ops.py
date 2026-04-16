from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query

from app.schemas.customer_ops import CustomerCompanyCreate
from app.services.customer_ops_service import create_customer, list_customers

router = APIRouter(prefix="/api/v1/customer-ops", tags=["customer-ops"])


@router.get("/health")
def customer_ops_health():
    return {"status": "ok", "service": "customer-ops"}


@router.get("/customers")
def list_customers_route(limit: int = Query(default=100, ge=1, le=500)):
    try:
        items = list_customers(limit=limit)
        return {"items": items}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_ops_list_failed: {exc}")


@router.post("/customers")
def create_customer_route(payload: CustomerCompanyCreate):
    try:
        item = create_customer(payload.model_dump())
        return item
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_ops_create_failed: {exc}")
