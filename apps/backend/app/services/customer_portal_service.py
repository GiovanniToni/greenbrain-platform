from __future__ import annotations

from typing import Any, Dict

from app.repositories.customer_portal_repository import get_customer_by_portal_email


def build_customer_portal_profile(user_email: str) -> Dict[str, Any]:
    row = get_customer_by_portal_email(user_email)
    if not row:
        raise RuntimeError(f"customer_portal_profile_not_found_for_email: {user_email}")

    delivery = row.get("delivery") or {}

    return {
        "customer_id": row.get("customer_id"),
        "tenant_code": row.get("tenant_code"),
        "company_name": row.get("company_name"),
        "contact_name": row.get("contact_name"),
        "contact_email": row.get("contact_email"),
        "contact_phone": row.get("contact_phone"),
        "city": row.get("city"),
        "country": row.get("country"),
        "portal_user_email": row.get("portal_user_email"),
        "signup_source": row.get("signup_source"),
        "signup_completed_at": row.get("signup_completed_at"),
        "onboarding_status": row.get("onboarding_status"),
        "onboarding_step": row.get("onboarding_step"),
        "db_integration_status": row.get("db_integration_status"),
        "assigned_release_version": row.get("assigned_release_version"),
        "installed_release_version": row.get("installed_release_version"),
        "created_at": row.get("created_at"),
        "updated_at": row.get("updated_at"),
        "delivery": {
            "assigned_release_version": delivery.get("assigned_release_version"),
            "bundle_generated_at": delivery.get("bundle_generated_at"),
            "bundle_sent_at": delivery.get("bundle_sent_at"),
            "bundle_local_path": delivery.get("bundle_local_path"),
            "install_status": delivery.get("install_status"),
            "onboarding_status": delivery.get("onboarding_status"),
            "go_live_at": delivery.get("go_live_at"),
            "updated_at": delivery.get("updated_at"),
        },
    }
