from __future__ import annotations

from typing import Any, Dict

from app.integrations.supabase_client import get_supabase_client


def assign_release_to_customer(customer_id: str, assigned_release_version: str) -> Dict[str, Any]:
    client = get_supabase_client()

    company_resp = (
        client.table("gb_customer_companies")
        .update({"assigned_release_version": assigned_release_version})
        .eq("customer_id", customer_id)
        .execute()
    )

    company_rows = company_resp.data or []
    if not company_rows:
        raise RuntimeError(f"customer_not_found: {customer_id}")

    delivery_payload = {
        "customer_id": customer_id,
        "assigned_release_version": assigned_release_version,
        "onboarding_status": company_rows[0].get("onboarding_status") or "draft",
        "install_status": company_rows[0].get("install_status") or "not_started",
    }

    delivery_resp = (
        client.table("gb_customer_delivery")
        .upsert(delivery_payload, on_conflict="customer_id")
        .execute()
    )

    delivery_rows = delivery_resp.data or []

    return {
        "customer": company_rows[0],
        "delivery": delivery_rows[0] if delivery_rows else delivery_payload,
    }
