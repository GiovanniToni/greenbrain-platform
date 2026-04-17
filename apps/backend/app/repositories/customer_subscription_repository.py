from __future__ import annotations

from typing import Any, Dict, Optional

from app.integrations.supabase_client import get_supabase_client


def get_customer_company(customer_id: str) -> Optional[Dict[str, Any]]:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_companies")
        .select("*")
        .eq("customer_id", customer_id)
        .limit(1)
        .execute()
    )
    rows = resp.data or []
    return rows[0] if rows else None


def get_customer_company_by_portal_email(portal_user_email: str) -> Optional[Dict[str, Any]]:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_companies")
        .select("*")
        .eq("portal_user_email", portal_user_email)
        .limit(1)
        .execute()
    )
    rows = resp.data or []
    return rows[0] if rows else None


def upsert_customer_subscription(payload: Dict[str, Any]) -> Dict[str, Any]:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_subscriptions")
        .upsert(payload, on_conflict="customer_id")
        .execute()
    )
    rows = resp.data or []
    if not rows:
        raise RuntimeError("customer_subscription_upsert_failed")
    return rows[0]


def update_customer_company_subscription_fields(customer_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_companies")
        .update(payload)
        .eq("customer_id", customer_id)
        .execute()
    )
    rows = resp.data or []
    if not rows:
        raise RuntimeError("customer_company_subscription_update_failed")
    return rows[0]
