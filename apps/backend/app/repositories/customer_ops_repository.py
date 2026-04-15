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
