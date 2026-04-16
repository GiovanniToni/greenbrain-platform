from __future__ import annotations

from typing import Any, Dict, List

from app.integrations.supabase_client import get_supabase_client


def list_customer_companies(limit: int = 100) -> List[Dict[str, Any]]:
    client = get_supabase_client()

    response = (
        client.table("gb_customer_companies")
        .select(
            """
            customer_id,
            tenant_code,
            company_name,
            contact_name,
            contact_email,
            contact_phone,
            onboarding_status,
            install_status,
            db_integration_status,
            assigned_release_version,
            installed_release_version,
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
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
    )

    rows = response.data or []
    normalized: List[Dict[str, Any]] = []

    for row in rows:
        delivery = row.get("gb_customer_delivery")
        if isinstance(delivery, list):
            delivery = delivery[0] if delivery else None

        normalized.append(
            {
                "customer_id": row.get("customer_id"),
                "tenant_code": row.get("tenant_code"),
                "company_name": row.get("company_name"),
                "contact_name": row.get("contact_name"),
                "contact_email": row.get("contact_email"),
                "contact_phone": row.get("contact_phone"),
                "onboarding_status": row.get("onboarding_status"),
                "install_status": row.get("install_status"),
                "db_integration_status": row.get("db_integration_status"),
                "assigned_release_version": row.get("assigned_release_version"),
                "installed_release_version": row.get("installed_release_version"),
                "created_at": row.get("created_at"),
                "updated_at": row.get("updated_at"),
                "delivery_assigned_release_version": (delivery or {}).get("assigned_release_version"),
                "bundle_generated_at": (delivery or {}).get("bundle_generated_at"),
                "bundle_sent_at": (delivery or {}).get("bundle_sent_at"),
                "bundle_local_path": (delivery or {}).get("bundle_local_path"),
                "delivery_install_status": (delivery or {}).get("install_status"),
                "delivery_onboarding_status": (delivery or {}).get("onboarding_status"),
                "go_live_at": (delivery or {}).get("go_live_at"),
                "delivery_updated_at": (delivery or {}).get("updated_at"),
            }
        )

    return normalized
