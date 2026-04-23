from __future__ import annotations

from typing import Any, Dict, Optional

from app.integrations.supabase_client import get_supabase_client


def get_customer_by_portal_email(portal_user_email: str) -> Optional[Dict[str, Any]]:
    client = get_supabase_client()

    resp = (
        client.table("gb_customer_companies")
        .select(
            """
            customer_id,
            tenant_code,
            company_name,
            contact_name,
            contact_email,
            contact_phone,
            city,
            country,
            onboarding_status,
            onboarding_step,
            db_integration_status,
            assigned_release_version,
            installed_release_version,
            last_downloaded_release_version,
            last_downloaded_at,
            signup_source,
            signup_completed_at,
            portal_user_email,
            subscription_status,
            subscription_plan,
            billing_email,
            payment_method_id,
            payment_method_last4,
            payment_method_brand,
            stripe_customer_id,
            setup_slot_preferred_date,
            setup_slot_preferred_time,
            setup_slot_requested_at,
            setup_slot_confirmed_at,
            setup_slot_scheduled_for,
            data_validated_at,
            cancellation_requested,
            cancellation_requested_at,
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
        )
        .eq("portal_user_email", portal_user_email)
        .limit(1)
        .execute()
    )

    rows = resp.data or []
    if not rows:
        return None

    row = rows[0]
    delivery = row.get("gb_customer_delivery")
    if isinstance(delivery, list):
        delivery = delivery[0] if delivery else None

    row["delivery"] = delivery
    row.pop("gb_customer_delivery", None)
    return row


def update_customer_portal_fields(portal_user_email: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_companies")
        .update(payload)
        .eq("portal_user_email", portal_user_email)
        .execute()
    )
    rows = resp.data or []
    if not rows:
        raise RuntimeError(f"customer_portal_fields_update_failed:{portal_user_email}")
    return rows[0]


def update_customer_last_download(
    customer_id: str,
    last_downloaded_release_version: str,
    last_downloaded_at: str,
):
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_companies")
        .update(
            {
                "last_downloaded_release_version": last_downloaded_release_version,
                "last_downloaded_at": last_downloaded_at,
            }
        )
        .eq("customer_id", customer_id)
        .execute()
    )
    rows = resp.data or []
    return rows[0] if rows else {
        "customer_id": customer_id,
        "last_downloaded_release_version": last_downloaded_release_version,
        "last_downloaded_at": last_downloaded_at,
    }
