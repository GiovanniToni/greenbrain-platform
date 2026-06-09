from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from sqlalchemy import text

from app.repositories.customer_ops_repository import (
    create_customer_company,
    get_customer_company_detail,
    get_customer_ops_item_by_id,
    list_customer_companies,
    update_customer_company_onboarding,
)
from app.services.customer_billing_service import (
    activate_subscription_for_customer,
    cancel_subscription_at_period_end,
    force_activate_subscription_for_customer as _force_activate,
)
from app.services.customer_delivery_service import prepare_delivery_plan, get_latest_available_release_version
from app.services.customer_provisioning_service import assign_release as provisioning_assign_release
from app.services.password_reset_service import create_password_reset_for_email
from app.db.session import SessionLocal
from app.repositories.customer_security_alerts_repository import list_active_admin_security_notifications, mark_password_reset_self_service_alert_link_sent_by_admin
from app.repositories.customer_source_db_repository import get_source_db_integration, mask_source_db_integration

logger = logging.getLogger(__name__)

_ALLOWED_OPS_TRANSITIONS = {
    "slot_confirmed",
    "setup_in_progress",
    "data_validation_pending",
}


def normalize_delivery_state(item: Dict[str, Any]) -> str:
    """
    Derive a canonical delivery_status from an ops item's delivery fields.
    Guarantees return value is one of: pending, prepared, sent, installed, failed.
    Also logs data-consistency warnings when bundle fields are in an incoherent state.
    """
    install_st = (item.get("delivery_install_status") or "").lower()
    if install_st == "installed":
        return "installed"
    if "failed" in install_st or "error" in install_st:
        return "failed"

    bundle_generated = item.get("bundle_generated_at")
    bundle_path = item.get("bundle_local_path")
    bundle_sent = item.get("bundle_sent_at")

    if bundle_sent and not bundle_generated:
        logger.warning(
            "[normalize_delivery_state] customer=%s: bundle_sent_at set but bundle_generated_at missing",
            item.get("customer_id"),
        )
        return "sent"

    if bundle_generated and not bundle_path:
        logger.warning(
            "[normalize_delivery_state] customer=%s: bundle_generated_at set but bundle_local_path missing",
            item.get("customer_id"),
        )
        return "failed"

    if bundle_sent:
        return "sent"
    if bundle_generated and bundle_path:
        return "prepared"
    return "pending"


def _iso_or_none(value: Any) -> Optional[str]:
    if value is None:
        return None
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


def _enrich_password_reset_history(item: Dict[str, Any]) -> None:
    """
    Add last completed password-reset metadata to customer detail.

    Source of truth is greenbrain_users password tracking. We only expose this
    as a reset history when password_change_source='password_reset'.
    """
    item["last_password_reset_at"] = None
    item["last_password_reset_password_version"] = None
    item["last_password_reset_sync_status"] = None
    item["last_password_reset_synced_at"] = None

    email = (
        item.get("portal_user_email")
        or item.get("contact_email")
        or item.get("billing_email")
        or ""
    ).strip().lower()
    if not email:
        return

    db = SessionLocal()
    try:
        row = db.execute(
            text("""
                SELECT
                  password_changed_at,
                  password_version,
                  password_last_sync_status,
                  password_last_synced_at
                FROM public.greenbrain_users
                WHERE lower(email) = lower(:email)
                  AND password_change_source = 'password_reset'
                  AND password_changed_at IS NOT NULL
                ORDER BY password_changed_at DESC
                LIMIT 1
            """),
            {"email": email},
        ).mappings().first()
    finally:
        db.close()

    if not row:
        return

    item["last_password_reset_at"] = _iso_or_none(row.get("password_changed_at"))
    item["last_password_reset_password_version"] = row.get("password_version")
    item["last_password_reset_sync_status"] = row.get("password_last_sync_status")
    item["last_password_reset_synced_at"] = _iso_or_none(row.get("password_last_synced_at"))


def get_customer_ops_item(customer_id: str) -> Dict[str, Any]:
    """Return a fully-enriched ops item (company + delivery join + derived delivery_status)."""
    item = get_customer_ops_item_by_id(customer_id)
    if not item:
        raise ValueError(f"customer_not_found:{customer_id}")
    item["delivery_status"] = normalize_delivery_state(item)
    _enrich_password_reset_history(item)
    item["source_db_integration"] = mask_source_db_integration(
        get_source_db_integration(customer_id)
    )
    item["latest_available_release_version"] = get_latest_available_release_version()
    return item


def send_release(customer_id: str, release_version: str) -> Dict[str, Any]:
    """
    Atomic send-release:
      Step 1 — assign release via provisioning service:
               writes assigned_release_version to gb_customer_companies
               AND upserts a delivery row in gb_customer_delivery.
               If this fails → stop, return error (nothing written to delivery).
      Step 2 — validate delivery readiness via delivery service.
               If this fails → return error, no silent continuation.
    Returns a unified snapshot: customer_id, assigned_release_version,
    bundle_generated_at, bundle_local_path, delivery_status.
    """
    customer = get_customer_company_detail(customer_id)
    if not customer:
        raise ValueError(f"customer_not_found:{customer_id}")

    logger.info("[send_release] step1: assigning release=%s to customer=%s", release_version, customer_id)
    provisioning_assign_release(customer_id, release_version)
    logger.info("[send_release] step1: OK")

    logger.info("[send_release] step2: prepare delivery for customer=%s", customer_id)
    try:
        delivery_plan = prepare_delivery_plan(customer_id)
    except Exception as exc:
        logger.error("[send_release] step2: prepare failed: %s", exc)
        raise ValueError(f"prepare_delivery_failed:{exc}") from exc
    logger.info("[send_release] step2: OK — status=%s", delivery_plan.get("status"))

    updated = get_customer_ops_item_by_id(customer_id) or {}
    return {
        "customer_id": customer_id,
        "assigned_release_version": release_version,
        "bundle_generated_at": updated.get("bundle_generated_at"),
        "bundle_local_path": updated.get("bundle_local_path"),
        "delivery_status": normalize_delivery_state(updated),
    }


def list_customers(limit: int = 100) -> List[Dict[str, Any]]:
    """Return ops list items enriched with the same release/runtime state used by detail."""
    latest_available = get_latest_available_release_version()
    items = list_customer_companies(limit=limit)

    for item in items:
        item["delivery_status"] = normalize_delivery_state(item)
        item["latest_available_release_version"] = latest_available

    return items


def list_customer_ops_notifications(limit: int = 20) -> Dict[str, Any]:
    """Return active internal-admin notifications for the ops bell."""
    db = SessionLocal()
    try:
        items = list_active_admin_security_notifications(db, limit=limit)
    finally:
        db.close()

    return {
        "items": items,
        "active_count": len(items),
        "unread_count": len(items),
    }


def create_customer(payload: Dict[str, Any]) -> Dict[str, Any]:
    return create_customer_company(payload)


def update_customer_onboarding_status(
    customer_id: str,
    new_status: str,
    step: Optional[str] = None,
    notes: Optional[str] = None,
) -> Dict[str, Any]:
    if new_status not in _ALLOWED_OPS_TRANSITIONS:
        allowed = ", ".join(sorted(_ALLOWED_OPS_TRANSITIONS))
        raise ValueError(f"invalid_onboarding_status:{new_status}. Allowed: {allowed}")

    if new_status == "slot_confirmed":
        customer = get_customer_company_detail(customer_id)
        if not customer or not customer.get("setup_slot_scheduled_for"):
            raise ValueError("slot_confirmed_requires_setup_slot_scheduled_for: use confirm-slot endpoint")

    now_iso = datetime.now(timezone.utc).isoformat()
    update_customer_company_onboarding(customer_id, {
        "onboarding_status": new_status,
        "onboarding_step": step or new_status,
        "updated_at": now_iso,
    })
    return {"customer_id": customer_id, "onboarding_status": new_status, "updated_at": now_iso}


def confirm_customer_setup_slot(
    customer_id: str,
    scheduled_for: str,
    notes: Optional[str] = None,
) -> Dict[str, Any]:
    customer = get_customer_company_detail(customer_id)
    if not customer:
        raise RuntimeError(f"customer_not_found:{customer_id}")

    if not customer.get("setup_slot_requested_at"):
        raise RuntimeError("cannot_confirm_slot_no_request")
    if customer.get("setup_slot_confirmed_at") and customer.get("setup_slot_scheduled_for"):
        raise RuntimeError("slot_already_confirmed")

    current_status = (customer.get("onboarding_status") or "").strip()
    now_iso = datetime.now(timezone.utc).isoformat()
    fields: Dict[str, Any] = {
        "setup_slot_confirmed_at": now_iso,
        "setup_slot_scheduled_for": scheduled_for,
        "updated_at": now_iso,
    }
    if current_status == "slot_requested":
        fields["onboarding_status"] = "slot_confirmed"
        fields["onboarding_step"] = "slot_confirmed"
    update_customer_company_onboarding(customer_id, fields)
    result_status = "slot_confirmed" if current_status == "slot_requested" else current_status
    return {
        "customer_id": customer_id,
        "onboarding_status": result_status,
        "setup_slot_scheduled_for": scheduled_for,
    }


def trigger_subscription_activation(customer_id: str) -> Dict[str, Any]:
    return activate_subscription_for_customer(customer_id)


def force_activate_subscription(customer_id: str) -> Dict[str, Any]:
    return _force_activate(customer_id)


def mark_customer_password_reset_alert_link_sent(
    customer_id: str,
    *,
    admin_user_id: str | None = None,
) -> Dict[str, Any]:
    """
    Mark the active self-service password reset alert as link-sent by admin.
    This does not resolve the alert and does not change/revoke any password reset token.
    """
    customer = get_customer_company_detail(customer_id)
    if not customer:
        raise ValueError(f"customer_not_found:{customer_id}")

    email = (
        customer.get("portal_user_email")
        or customer.get("contact_email")
        or customer.get("billing_email")
        or ""
    ).strip().lower()
    if not email:
        raise ValueError(f"customer_password_reset_email_missing:{customer_id}")

    db = SessionLocal()
    try:
        alert = mark_password_reset_self_service_alert_link_sent_by_admin(
            db,
            customer_id=customer_id,
            email=email,
            tenant_code=customer.get("tenant_code"),
            admin_user_id=admin_user_id,
            details={
                "customer_id": customer_id,
                "tenant_code": customer.get("tenant_code"),
                "marked_from": "customer_ops_detail",
            },
        )
    finally:
        db.close()

    return {
        "status": alert.get("status") or "email_sent",
        "customer_id": customer_id,
        "email": email,
        "alert_id": str(alert.get("id")) if alert.get("id") else None,
        "updated_count": 1,
    }


def generate_customer_password_reset_link(
    db,
    customer_id: str,
    *,
    created_by_user_id: str | None = None,
    frontend_base_url: str = "https://www.greenbrain.it",
    expires_minutes: int = 60,
) -> Dict[str, Any]:
    """
    Generate an admin-created password reset link for a customer's portal user.

    Safety:
      - Does not change the password.
      - Stores only token_hash in DB through password_reset_service.
      - Returns the raw token only embedded in reset_url for immediate admin copy.
      - Does not expose token_hash.
    """
    customer = get_customer_company_detail(customer_id)
    if not customer:
        raise ValueError(f"customer_not_found:{customer_id}")

    email = (
        customer.get("portal_user_email")
        or customer.get("contact_email")
        or customer.get("billing_email")
        or ""
    ).strip().lower()
    if not email:
        raise ValueError(f"customer_password_reset_email_missing:{customer_id}")

    created = create_password_reset_for_email(
        db,
        email=email,
        source="admin",
        frontend_base_url=frontend_base_url,
        created_by_user_id=created_by_user_id,
        expires_minutes=expires_minutes,
    )

    if created.get("status") != "created" or not created.get("reset_url"):
        raise ValueError(f"customer_password_reset_user_not_found:{email}")

    expires_at = created.get("expires_at")
    if hasattr(expires_at, "isoformat"):
        expires_at = expires_at.isoformat()

    return {
        "status": "created",
        "customer_id": customer_id,
        "tenant_code": customer.get("tenant_code"),
        "company_name": customer.get("company_name"),
        "email": created.get("email"),
        "reset_url": created.get("reset_url"),
        "token_hint": created.get("token_hint"),
        "expires_at": expires_at,
        "expires_minutes": expires_minutes,
        "source": "admin",
        "safety": {
            "token_hash_exposed": False,
            "password_changed": False,
            "raw_token_stored": False,
        },
    }


def request_cancellation(customer_id: str) -> Dict[str, Any]:
    """
    Mark a customer as requesting cancellation and set cancel_at_period_end on Stripe.
    If stripe_subscription_id is missing, the DB fields are still written and Stripe is skipped.
    """
    customer = get_customer_company_detail(customer_id)
    if not customer:
        raise ValueError(f"customer_not_found:{customer_id}")

    result = cancel_subscription_at_period_end(customer_id)
    logger.info(
        "[request_cancellation] customer=%s stripe_updated=%s",
        customer_id, result.get("stripe_updated"),
    )
    return result
