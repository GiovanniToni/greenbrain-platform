from __future__ import annotations

from typing import Any, Dict, List

from app.integrations.supabase_client import get_supabase_client


def list_customer_companies(limit: int = 100) -> List[Dict[str, Any]]:
    client = get_supabase_client()

    response = (
        client.table("gb_customer_companies")
        .select(
            "customer_id,tenant_code,company_name,contact_name,contact_email,"
            "contact_phone,onboarding_status,install_status,db_integration_status,"
            "assigned_release_version,installed_release_version,created_at,updated_at"
        )
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
    )

    return response.data or []


def create_customer_company(data: Dict[str, Any]) -> Dict[str, Any]:
    client = get_supabase_client()

    payload = {
        "tenant_code": data.get("tenant_code"),
        "company_name": data["company_name"],
        "vat_number": data.get("vat_number"),
        "contact_name": data.get("contact_name"),
        "contact_email": data["contact_email"],
        "contact_phone": data.get("contact_phone"),
        "city": data.get("city"),
        "country": data.get("country"),
        "onboarding_status": data.get("onboarding_status") or "draft",
        "install_status": data.get("install_status") or "not_started",
        "db_integration_status": data.get("db_integration_status") or "not_started",
        "assigned_release_version": data.get("assigned_release_version"),
        "installed_release_version": data.get("installed_release_version"),
        "notes": data.get("notes"),
    }

    response = (
        client.table("gb_customer_companies")
        .insert(payload)
        .execute()
    )

    if not response.data:
        raise RuntimeError(f"insert_failed: {response}")

    return response.data[0]
