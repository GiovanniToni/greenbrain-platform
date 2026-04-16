from __future__ import annotations

from typing import Any, Dict

from app.integrations.supabase_client import get_supabase_client


def get_customer_by_id(customer_id: str) -> Dict[str, Any]:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_companies")
        .select("*")
        .eq("customer_id", customer_id)
        .limit(1)
        .execute()
    )
    rows = resp.data or []
    if not rows:
        raise RuntimeError(f"customer_not_found: {customer_id}")
    return rows[0]


def upsert_customer_delivery(
    customer_id: str,
    assigned_release_version: str,
    bundle_generated_at: str,
    bundle_local_path: str,
    onboarding_status: str,
    install_status: str,
) -> Dict[str, Any]:
    client = get_supabase_client()

    payload = {
        "customer_id": customer_id,
        "assigned_release_version": assigned_release_version,
        "bundle_generated_at": bundle_generated_at,
        "bundle_local_path": bundle_local_path,
        "onboarding_status": onboarding_status,
        "install_status": install_status,
    }

    resp = (
        client.table("gb_customer_delivery")
        .upsert(payload, on_conflict="customer_id")
        .execute()
    )
    rows = resp.data or []
    return rows[0] if rows else payload


def mark_bundle_sent(customer_id: str, bundle_sent_at: str) -> Dict[str, Any]:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_delivery")
        .update({"bundle_sent_at": bundle_sent_at})
        .eq("customer_id", customer_id)
        .execute()
    )
    rows = resp.data or []
    return rows[0] if rows else {"customer_id": customer_id, "bundle_sent_at": bundle_sent_at}
