from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from app.repositories.customer_ops_repository import (
    create_customer_company,
    get_customer_company_detail,
    list_customer_companies,
    update_customer_company_onboarding,
)
from app.services.customer_billing_service import activate_subscription_for_customer

_ALLOWED_OPS_TRANSITIONS = {
    "slot_confirmed",
    "setup_in_progress",
    "data_validation_pending",
    "data_validated",
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
