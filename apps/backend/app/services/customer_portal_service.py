from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Any, Dict

from app.repositories.customer_portal_repository import (
    get_customer_by_portal_email,
    update_customer_portal_fields,
)
from app.services.customer_billing_service import (
    cancel_subscription_at_period_end_for_portal_email,
)
from app.services.customer_delivery_service import get_latest_available_release_version

_SLOT_STATES_ALREADY_BOOKED = {
    "slot_requested",
    "slot_confirmed",
    "setup_in_progress",
    "data_validation_pending",
    "data_validated",
}


def build_customer_portal_profile(user_email: str) -> Dict[str, Any]:
    row = get_customer_by_portal_email(user_email)
    if not row:
        raise RuntimeError(f"customer_portal_profile_not_found_for_email: {user_email}")

    delivery = row.get("delivery") or {}
    latest_available_release_version = get_latest_available_release_version()

    return {
        "customer_id": row.get("customer_id"),
        "tenant_code": row.get("tenant_code"),
        "company_name": row.get("company_name"),
        "contact_name": row.get("contact_name"),
        "contact_email": row.get("contact_email"),
        "contact_phone": row.get("contact_phone"),
        "city": row.get("city"),
        "country": row.get("country"),
        "portal_user_email": row.get("portal_user_email"),
        "signup_source": row.get("signup_source"),
        "signup_completed_at": row.get("signup_completed_at"),
        "onboarding_status": row.get("onboarding_status"),
        "onboarding_step": row.get("onboarding_step"),
        "db_integration_status": row.get("db_integration_status"),
        "assigned_release_version": row.get("assigned_release_version"),
        "installed_release_version": row.get("installed_release_version"),
        "last_downloaded_release_version": row.get("last_downloaded_release_version"),
        "last_downloaded_at": row.get("last_downloaded_at"),
        "latest_available_release_version": latest_available_release_version,
        "subscription_status": row.get("subscription_status"),
        "subscription_plan": row.get("subscription_plan"),
        "payment_method_saved": bool(row.get("payment_method_id")),
        "payment_method_last4": row.get("payment_method_last4"),
        "payment_method_brand": row.get("payment_method_brand"),
        "setup_slot_preferred_date": str(row.get("setup_slot_preferred_date") or "") or None,
        "setup_slot_preferred_time": row.get("setup_slot_preferred_time"),
        "setup_slot_requested_at": row.get("setup_slot_requested_at"),
        "setup_slot_confirmed_at": row.get("setup_slot_confirmed_at"),
        "setup_slot_scheduled_for": row.get("setup_slot_scheduled_for"),
        "data_validated_at": row.get("data_validated_at"),
        "cancellation_requested": bool(row.get("cancellation_requested")),
        "cancellation_requested_at": row.get("cancellation_requested_at"),
        "subscription_current_period_end": row.get("subscription_current_period_end"),
        "subscription_cancel_at_period_end": bool(row.get("subscription_cancel_at_period_end")),
        "created_at": row.get("created_at"),
        "updated_at": row.get("updated_at"),
        "delivery": {
            "assigned_release_version": delivery.get("assigned_release_version"),
            "bundle_generated_at": delivery.get("bundle_generated_at"),
            "bundle_sent_at": delivery.get("bundle_sent_at"),
            "bundle_local_path": delivery.get("bundle_local_path"),
            "install_status": delivery.get("install_status"),
            "onboarding_status": delivery.get("onboarding_status"),
            "go_live_at": delivery.get("go_live_at"),
            "updated_at": delivery.get("updated_at"),
        },
    }


def cancel_customer_portal_subscription(user_email: str) -> Dict[str, Any]:
    row = get_customer_by_portal_email(user_email)
    if not row:
        raise RuntimeError(f"customer_portal_profile_not_found_for_email: {user_email}")
    return cancel_subscription_at_period_end_for_portal_email(user_email)


def book_customer_setup_slot(user_email: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    row = get_customer_by_portal_email(user_email)
    if not row:
        raise RuntimeError(f"customer_portal_profile_not_found_for_email: {user_email}")

    preferred_time = (payload.get("preferred_time") or "").strip()
    if preferred_time not in ("morning", "afternoon"):
        raise RuntimeError("invalid_preferred_time: must be 'morning' or 'afternoon'")

    preferred_date_str = (payload.get("preferred_date") or "").strip()
    try:
        preferred_date = date.fromisoformat(preferred_date_str)
    except (ValueError, TypeError):
        raise RuntimeError("invalid_preferred_date: must be ISO format YYYY-MM-DD")

    today = datetime.now(timezone.utc).date()
    if preferred_date <= today:
        raise RuntimeError("invalid_preferred_date: must be a future date")

    current_status = (row.get("onboarding_status") or "").strip()
    if current_status in _SLOT_STATES_ALREADY_BOOKED:
        raise RuntimeError("slot_already_requested")

    notes = (payload.get("notes") or "").strip() or None
    now_iso = datetime.now(timezone.utc).isoformat()

    update_customer_portal_fields(user_email, {
        "setup_slot_preferred_date": preferred_date_str,
        "setup_slot_preferred_time": preferred_time,
        "setup_slot_requested_at": now_iso,
        "setup_slot_notes": notes,
        "onboarding_status": "slot_requested",
        "onboarding_step": "slot_requested",
        "updated_at": now_iso,
    })

    return {
        "status": "slot_requested",
        "preferred_date": preferred_date_str,
        "preferred_time": preferred_time,
    }


def confirm_customer_data_ok(user_email: str) -> Dict[str, Any]:
    row = get_customer_by_portal_email(user_email)
    if not row:
        raise RuntimeError(f"customer_portal_profile_not_found_for_email: {user_email}")

    current_status = (row.get("onboarding_status") or "").strip()
    if current_status != "data_validation_pending":
        raise RuntimeError("data_not_ready_for_validation")

    if not (row.get("payment_method_id") or "").strip():
        raise RuntimeError("payment_method_missing")

    now_iso = datetime.now(timezone.utc).isoformat()
    update_customer_portal_fields(user_email, {
        "onboarding_status": "data_validated",
        "onboarding_step": "data_validated",
        "data_validated_at": now_iso,
        "updated_at": now_iso,
    })

    return {
        "status": "data_validated",
        "data_validated_at": now_iso,
    }
