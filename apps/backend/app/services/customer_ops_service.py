from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

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
from app.services.customer_delivery_service import prepare_delivery_plan
from app.services.customer_provisioning_service import assign_release as provisioning_assign_release

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


def get_customer_ops_item(customer_id: str) -> Dict[str, Any]:
    """Return a fully-enriched ops item (company + delivery join + derived delivery_status)."""
    item = get_customer_ops_item_by_id(customer_id)
    if not item:
        raise ValueError(f"customer_not_found:{customer_id}")
    item["delivery_status"] = normalize_delivery_state(item)
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
    return list_customer_companies(limit=limit)


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

    current_status = (customer.get("onboarding_status") or "").strip()
    if current_status != "slot_requested":
        raise RuntimeError("cannot_confirm_slot_in_current_state")

    now_iso = datetime.now(timezone.utc).isoformat()
    update_customer_company_onboarding(customer_id, {
        "setup_slot_confirmed_at": now_iso,
        "setup_slot_scheduled_for": scheduled_for,
        "onboarding_status": "slot_confirmed",
        "onboarding_step": "slot_confirmed",
        "updated_at": now_iso,
    })
    return {
        "customer_id": customer_id,
        "onboarding_status": "slot_confirmed",
        "setup_slot_scheduled_for": scheduled_for,
    }


def trigger_subscription_activation(customer_id: str) -> Dict[str, Any]:
    return activate_subscription_for_customer(customer_id)


def force_activate_subscription(customer_id: str) -> Dict[str, Any]:
    return _force_activate(customer_id)


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
