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


_RUNTIME_CONNECTION_SELECT = """
    tenant_code,
    runtime_health,
    installation_id,
    public_backend_url,
    local_backend_url,
    local_agent_version,
    connection_mode,
    last_heartbeat_at,
    last_sync_status,
    last_sync_at
"""


def _derive_installation_state(item: Dict[str, Any]) -> Dict[str, Any]:
    runtime_status = (item.get("runtime_connection_status") or "").strip().lower()
    installation_id = item.get("latest_installation_id")
    heartbeat = item.get("last_runtime_heartbeat_at")
    downloaded = bool(item.get("last_downloaded_at"))

    platform_ready = bool(runtime_status == "healthy" and installation_id and heartbeat)

    if platform_ready:
        status = "healthy"
        label = "Piattaforma attiva"
        next_action = "open_platform"
    elif installation_id:
        status = "registered"
        label = "Runtime registrato, in attesa stato healthy"
        next_action = "check_runtime"
    elif downloaded:
        status = "downloaded"
        label = "Bundle scaricato, installazione non ancora collegata"
        next_action = "complete_installation"
    else:
        status = "not_started"
        label = "Installazione non ancora iniziata"
        next_action = "download_bundle"

    return {
        "platform_ready": platform_ready,
        "installation_status": status,
        "installation_status_label": label,
        "installation_next_action": next_action,
    }


def _map_row_to_ops_item(row: Dict[str, Any], runtime: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """Normalize a raw gb_customer_companies row (with embedded gb_customer_delivery) into a CustomerOpsItem dict."""
    delivery = row.get("gb_customer_delivery")
    if isinstance(delivery, list):
        delivery = delivery[0] if delivery else {}
    delivery = delivery or {}
    runtime = runtime or {}

    item = {
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
        "runtime_connection_status": runtime.get("runtime_health") or row.get("runtime_connection_status"),
        "latest_installation_id": runtime.get("installation_id") or row.get("latest_installation_id"),
        "last_runtime_heartbeat_at": runtime.get("last_heartbeat_at") or row.get("last_runtime_heartbeat_at"),
        "runtime_public_backend_url": runtime.get("public_backend_url"),
        "runtime_local_backend_url": runtime.get("local_backend_url"),
        "runtime_local_agent_version": runtime.get("local_agent_version"),
        "runtime_connection_mode": runtime.get("connection_mode"),
        "runtime_last_sync_status": runtime.get("last_sync_status"),
        "runtime_last_sync_at": runtime.get("last_sync_at"),
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
    item.update(_derive_installation_state(item))
    return item


def get_runtime_connections_by_tenant_codes(tenant_codes: List[str]) -> Dict[str, Dict[str, Any]]:
    clean_codes = sorted({(code or "").strip() for code in tenant_codes if (code or "").strip()})
    if not clean_codes:
        return {}

    client = get_supabase_client()
    resp = (
        client.table("greenbrain_runtime_connections")
        .select(_RUNTIME_CONNECTION_SELECT)
        .in_("tenant_code", clean_codes)
        .execute()
    )

    return {row.get("tenant_code"): row for row in (resp.data or []) if row.get("tenant_code")}


def list_customer_companies(limit: int = 100) -> List[Dict[str, Any]]:
    client = get_supabase_client()
    response = (
        client.table("gb_customer_companies")
        .select(_COMPANY_WITH_DELIVERY_SELECT)
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
    )
    rows = response.data or []
    runtime_map = get_runtime_connections_by_tenant_codes([row.get("tenant_code") for row in rows])
    return [_map_row_to_ops_item(row, runtime_map.get(row.get("tenant_code"))) for row in rows]


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
    row = rows[0]
    runtime_map = get_runtime_connections_by_tenant_codes([row.get("tenant_code")])
    return _map_row_to_ops_item(row, runtime_map.get(row.get("tenant_code")))


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
