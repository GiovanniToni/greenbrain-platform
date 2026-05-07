from __future__ import annotations

from typing import Any, Dict, List, Optional

from app.integrations.supabase_client import get_supabase_client


_COMPANY_WITH_DELIVERY_SELECT = """
    customer_id,
    tenant_code,
    company_name,
    contact_name,
    contact_email,
    contact_phone,
    portal_user_email,
    onboarding_status,
    onboarding_step,
    install_status,
    db_integration_status,
    assigned_release_version,
    installed_release_version,
    runtime_connection_status,
    latest_installation_id,
    last_runtime_heartbeat_at,
    first_downloaded_release_version,
    first_downloaded_at,
    last_downloaded_release_version,
    last_downloaded_at,
    subscription_status,
    subscription_plan,
    billing_email,
    payment_method_last4,
    payment_method_brand,
    payment_method_id,
    stripe_customer_id,
    setup_slot_preferred_date,
    setup_slot_preferred_time,
    setup_slot_requested_at,
    setup_slot_confirmed_at,
    setup_slot_scheduled_for,
    data_validated_at,
    cancellation_requested,
    cancellation_requested_at,
    subscription_current_period_end,
    subscription_activated_at,
    subscription_cancel_at_period_end,
    created_at,
    updated_at,
    gb_customer_delivery(
      assigned_release_version,
      bundle_generated_at,
      bundle_sent_at,
      bundle_local_path,
      install_status,
      onboarding_status,
      go_live_at,
      updated_at
    )
"""


def _map_row_to_ops_item(row: Dict[str, Any]) -> Dict[str, Any]:
    """Normalize a raw gb_customer_companies row (with embedded gb_customer_delivery) into a CustomerOpsItem dict."""
    delivery = row.get("gb_customer_delivery")
    if isinstance(delivery, list):
        delivery = delivery[0] if delivery else {}
    delivery = delivery or {}

    return {
        "customer_id": row.get("customer_id"),
        "tenant_code": row.get("tenant_code"),
        "company_name": row.get("company_name"),
        "contact_name": row.get("contact_name"),
        "contact_email": row.get("contact_email"),
        "contact_phone": row.get("contact_phone"),
        "portal_user_email": row.get("portal_user_email"),
        "onboarding_status": row.get("onboarding_status"),
        "onboarding_step": row.get("onboarding_step"),
        "install_status": row.get("install_status"),
        "db_integration_status": row.get("db_integration_status"),
        "assigned_release_version": row.get("assigned_release_version"),
        "installed_release_version": row.get("installed_release_version"),
        "runtime_connection_status": row.get("runtime_connection_status"),
        "latest_installation_id": row.get("latest_installation_id"),
        "last_runtime_heartbeat_at": row.get("last_runtime_heartbeat_at"),
        "first_downloaded_release_version": row.get("first_downloaded_release_version"),
        "first_downloaded_at": row.get("first_downloaded_at"),
        "last_downloaded_release_version": row.get("last_downloaded_release_version"),
        "last_downloaded_at": row.get("last_downloaded_at"),
        "subscription_status": row.get("subscription_status"),
        "subscription_activated_at": row.get("subscription_activated_at"),
        "subscription_plan": row.get("subscription_plan"),
        "billing_email": row.get("billing_email"),
        "payment_method_saved": bool(row.get("payment_method_id")),
        "payment_method_last4": row.get("payment_method_last4"),
        "payment_method_brand": row.get("payment_method_brand"),
        "stripe_customer_id": row.get("stripe_customer_id"),
        "setup_slot_preferred_date": str(row.get("setup_slot_preferred_date") or "") or None,
        "setup_slot_preferred_time": row.get("setup_slot_preferred_time"),
        "setup_slot_requested_at": row.get("setup_slot_requested_at"),
        "setup_slot_confirmed_at": row.get("setup_slot_confirmed_at"),
        "setup_slot_scheduled_for": row.get("setup_slot_scheduled_for"),
        "data_validated_at": row.get("data_validated_at"),
        "cancellation_requested": row.get("cancellation_requested", False),
        "cancellation_requested_at": row.get("cancellation_requested_at"),
        "subscription_current_period_end": row.get("subscription_current_period_end"),
        "subscription_cancel_at_period_end": bool(row.get("subscription_cancel_at_period_end")),
        "created_at": row.get("created_at"),
        "updated_at": row.get("updated_at"),
        "delivery_assigned_release_version": delivery.get("assigned_release_version"),
        "bundle_generated_at": delivery.get("bundle_generated_at"),
        "bundle_sent_at": delivery.get("bundle_sent_at"),
        "bundle_local_path": delivery.get("bundle_local_path"),
        "delivery_install_status": delivery.get("install_status"),
        "delivery_onboarding_status": delivery.get("onboarding_status"),
        "go_live_at": delivery.get("go_live_at"),
        "delivery_updated_at": delivery.get("updated_at"),
    }


def list_customer_companies(limit: int = 100) -> List[Dict[str, Any]]:
    client = get_supabase_client()
    response = (
        client.table("gb_customer_companies")
        .select(_COMPANY_WITH_DELIVERY_SELECT)
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
    )
    return [_map_row_to_ops_item(row) for row in (response.data or [])]


def get_customer_ops_item_by_id(customer_id: str) -> Optional[Dict[str, Any]]:
    """Return a single fully-enriched ops item (company + delivery join), or None if not found."""
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_companies")
        .select(_COMPANY_WITH_DELIVERY_SELECT)
        .eq("customer_id", customer_id)
        .limit(1)
        .execute()
    )
    rows = resp.data or []
    if not rows:
        return None
    return _map_row_to_ops_item(rows[0])


def get_customer_company_detail(customer_id: str) -> Optional[Dict[str, Any]]:
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
        return None
    row = rows[0]
    row["payment_method_saved"] = bool(row.get("payment_method_id"))
    return row


def update_customer_company_onboarding(customer_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_companies")
        .update(payload)
        .eq("customer_id", customer_id)
        .execute()
    )
    rows = resp.data or []
    if not rows:
        raise RuntimeError(f"customer_onboarding_update_failed:{customer_id}")
    return rows[0]


def create_customer_company(payload: Dict[str, Any]) -> Dict[str, Any]:
    client = get_supabase_client()

    response = (
        client.table("gb_customer_companies")
        .insert(payload)
        .execute()
    )

    rows = response.data or []
    if not rows:
        raise RuntimeError("customer_create_failed")

    return rows[0]
