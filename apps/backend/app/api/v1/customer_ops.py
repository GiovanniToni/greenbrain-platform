from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel

from app.api.v1.auth import require_internal_admin
from app.schemas.customer_ops import CustomerCompanyCreate
from app.services.customer_ops_service import (
    confirm_customer_setup_slot,
    create_customer,
    force_activate_subscription,
    get_customer_ops_item,
    list_customers,
    request_cancellation,
    send_release,
    trigger_subscription_activation,
    update_customer_onboarding_status,
)

router = APIRouter(prefix="/api/v1/customer-ops", tags=["customer-ops"])


@router.get("/health")
def customer_ops_health():
    return {"status": "ok", "service": "customer-ops"}


class OnboardingStatusUpdate(BaseModel):
    onboarding_status: str
    onboarding_step: Optional[str] = None
    notes: Optional[str] = None


class ConfirmSlotPayload(BaseModel):
    setup_slot_scheduled_for: str
    notes: Optional[str] = None


@router.get("/customers")
def list_customers_route(
    _: dict = Depends(require_internal_admin),
    limit: int = Query(default=100, ge=1, le=500),
):
    try:
        items = list_customers(limit=limit)
        return {"items": items}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_ops_list_failed: {exc}")

class SendReleasePayload(BaseModel):
    release_version: str


@router.post("/customers")
def create_customer_route(
    payload: CustomerCompanyCreate,
    _: dict = Depends(require_internal_admin),
):
    try:
        row = create_customer(payload.model_dump())
        return row
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_ops_create_failed: {exc}")


@router.get("/customers/{customer_id}")
def get_customer_detail_route(
    customer_id: str,
    _: dict = Depends(require_internal_admin),
):
    try:
        return get_customer_ops_item(customer_id)
    except ValueError as exc:
        msg = str(exc)
        if "customer_not_found" in msg:
            raise HTTPException(status_code=404, detail=msg)
        raise HTTPException(status_code=400, detail=msg)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_ops_detail_failed: {exc}")



@router.post("/customers/{customer_id}/send-release")
def send_release_route(
    customer_id: str,
    payload: SendReleasePayload,
    _: dict = Depends(require_internal_admin),
):
    try:
        return send_release(customer_id, payload.release_version)
    except ValueError as exc:
        msg = str(exc)
        if "customer_not_found" in msg:
            raise HTTPException(status_code=404, detail=msg)
        raise HTTPException(status_code=400, detail=msg)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"send_release_failed: {exc}")


@router.patch("/customers/{customer_id}/onboarding-status")
def update_onboarding_status_route(
    customer_id: str,
    payload: OnboardingStatusUpdate,
    _: dict = Depends(require_internal_admin),
):
    try:
        return update_customer_onboarding_status(
            customer_id,
            payload.onboarding_status,
            payload.onboarding_step,
            payload.notes,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"onboarding_status_update_failed: {exc}")


@router.post("/customers/{customer_id}/confirm-slot")
def confirm_slot_route(
    customer_id: str,
    payload: ConfirmSlotPayload,
    _: dict = Depends(require_internal_admin),
):
    try:
        return confirm_customer_setup_slot(
            customer_id,
            payload.setup_slot_scheduled_for,
            payload.notes,
        )
    except RuntimeError as exc:
        msg = str(exc)
        if "cannot_confirm_slot" in msg or "slot_already_confirmed" in msg or "customer_not_found" in msg:
            raise HTTPException(status_code=409, detail=msg)
        raise HTTPException(status_code=500, detail=f"confirm_slot_failed: {exc}")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"confirm_slot_failed: {exc}")


@router.post("/customers/{customer_id}/request-cancellation")
def request_cancellation_route(
    customer_id: str,
    _: dict = Depends(require_internal_admin),
):
    try:
        return request_cancellation(customer_id)
    except ValueError as exc:
        msg = str(exc)
        if "customer_not_found" in msg:
            raise HTTPException(status_code=404, detail=msg)
        raise HTTPException(status_code=400, detail=msg)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"request_cancellation_failed: {exc}")


@router.post("/customers/{customer_id}/activate-subscription")
def activate_subscription_route(
    customer_id: str,
    _: dict = Depends(require_internal_admin),
):
    try:
        return trigger_subscription_activation(customer_id)
    except RuntimeError as exc:
        msg = str(exc)
        if any(x in msg for x in (
            "payment_method_missing",
            "enterprise_manual_activation",
            "subscription_already_active",
            "subscription_plan_missing",
            "stripe_customer_id_missing",
            "unknown_plan",
            "data_not_validated",
        )):
            raise HTTPException(status_code=409, detail=msg)
        raise HTTPException(status_code=500, detail=f"activate_subscription_failed: {exc}")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"activate_subscription_failed: {exc}")


@router.post("/customers/{customer_id}/force-activate-subscription")
def force_activate_subscription_route(
    customer_id: str,
    _: dict = Depends(require_internal_admin),
):
    try:
        return force_activate_subscription(customer_id)
    except RuntimeError as exc:
        msg = str(exc)
        if any(x in msg for x in (
            "payment_method_missing",
            "enterprise_manual_activation",
            "subscription_already_active",
            "subscription_plan_missing",
            "stripe_customer_id_missing",
            "unknown_plan",
        )):
            raise HTTPException(status_code=409, detail=msg)
        raise HTTPException(status_code=500, detail=f"force_activate_subscription_failed: {exc}")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"force_activate_subscription_failed: {exc}")
