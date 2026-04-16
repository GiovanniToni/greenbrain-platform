from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict

from app.repositories.customer_onboarding_repository import create_customer_onboarding


def _slugify(value: str) -> str:
    value = (value or "").strip().lower()
    out = []
    for ch in value:
        if ch.isalnum():
            out.append(ch)
        else:
            out.append("-")
    slug = "".join(out)
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug.strip("-")


def build_tenant_code(company_name: str, city: str | None = None) -> str:
    base = _slugify(company_name)
    city_part = _slugify(city or "")
    if city_part:
        return f"{base}-{city_part}"
    return base


def start_customer_onboarding(payload: Dict[str, Any]) -> Dict[str, Any]:
    company_name = (payload.get("company_name") or "").strip()
    contact_email = (payload.get("contact_email") or "").strip()
    city = (payload.get("city") or "").strip() or None

    if not company_name:
        raise RuntimeError("company_name_missing")
    if not contact_email:
        raise RuntimeError("contact_email_missing")

    tenant_code = (payload.get("tenant_code") or "").strip()
    if not tenant_code:
        tenant_code = build_tenant_code(company_name=company_name, city=city)

    row = create_customer_onboarding(
        {
            "tenant_code": tenant_code,
            "company_name": company_name,
            "vat_number": payload.get("vat_number"),
            "contact_name": payload.get("contact_name"),
            "contact_email": contact_email,
            "contact_phone": payload.get("contact_phone"),
            "address_line": payload.get("address_line"),
            "city": city,
            "country": payload.get("country"),
            "onboarding_status": "signup_started",
            "install_status": "not_started",
            "db_integration_status": "not_started",
            "assigned_release_version": payload.get("assigned_release_version"),
            "installed_release_version": None,
            "notes": payload.get("notes"),
            "signup_source": payload.get("signup_source") or "landing_page",
            "signup_completed_at": datetime.now(timezone.utc).isoformat(),
            "onboarding_step": "company_created",
            "portal_user_email": contact_email,
        }
    )

    return {
        "status": "signup_started",
        "customer": row,
    }
