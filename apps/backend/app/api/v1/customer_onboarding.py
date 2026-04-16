from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, EmailStr

from app.services.customer_onboarding_service import start_customer_onboarding

router = APIRouter(prefix="/api/v1/customer-onboarding", tags=["customer-onboarding"])


class CustomerSignupPayload(BaseModel):
    company_name: str
    contact_name: Optional[str] = None
    contact_email: EmailStr
    portal_password: str
    contact_phone: Optional[str] = None
    vat_number: Optional[str] = None
    address_line: Optional[str] = None
    city: Optional[str] = None
    country: Optional[str] = None
    tenant_code: Optional[str] = None
    assigned_release_version: Optional[str] = "0.1.12"
    signup_source: Optional[str] = "landing_page"
    notes: Optional[str] = None


@router.get("/health")
def customer_onboarding_health():
    return {"status": "ok", "service": "customer-onboarding"}


@router.post("/signup")
def customer_signup(payload: CustomerSignupPayload):
    try:
        return start_customer_onboarding(payload.model_dump())
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_onboarding_failed: {exc}")
