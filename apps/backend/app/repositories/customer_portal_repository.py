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
            signup_source,
            signup_completed_at,
            portal_user_email,
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
