from __future__ import annotations

from typing import Any, Dict

from app.integrations.supabase_client import get_supabase_client


def create_customer_onboarding(payload: Dict[str, Any]) -> Dict[str, Any]:
    client = get_supabase_client()

    resp = (
        client.table("gb_customer_companies")
        .insert(payload)
        .execute()
    )

    rows = resp.data or []
    if not rows:
        raise RuntimeError("customer_onboarding_insert_failed")

    return rows[0]


def tenant_code_exists(tenant_code: str) -> bool:
    client = get_supabase_client()

    resp = (
        client.table("gb_customer_companies")
        .select("customer_id")
        .eq("tenant_code", tenant_code)
        .limit(1)
        .execute()
    )

    rows = resp.data or []
    return len(rows) > 0
