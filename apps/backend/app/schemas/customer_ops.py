from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, EmailStr


class CustomerCompanyCreate(BaseModel):
    company_name: str
    contact_name: Optional[str] = None
    contact_email: EmailStr
    contact_phone: Optional[str] = None
    vat_number: Optional[str] = None
    city: Optional[str] = None
    country: Optional[str] = None
    tenant_code: Optional[str] = None
    onboarding_status: Optional[str] = "draft"
    install_status: Optional[str] = "not_started"
    db_integration_status: Optional[str] = "not_started"
    assigned_release_version: Optional[str] = None
    installed_release_version: Optional[str] = None
    notes: Optional[str] = None


class CustomerCompanyOut(BaseModel):
    customer_id: str
    tenant_code: Optional[str] = None
    company_name: str
    contact_name: Optional[str] = None
    contact_email: EmailStr
    contact_phone: Optional[str] = None
    onboarding_status: str
    install_status: str
    db_integration_status: str
    assigned_release_version: Optional[str] = None
    installed_release_version: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class CustomerOpsSummary(BaseModel):
    customer_id: str
    company_name: str
    tenant_code: Optional[str] = None
    contact_email: EmailStr
    onboarding_status: str
    install_status: str
    db_integration_status: str
    assigned_release_version: Optional[str] = None
    installed_release_version: Optional[str] = None
    subscription_status: Optional[str] = None
