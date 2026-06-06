from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from fastapi.responses import FileResponse
from pydantic import BaseModel

from app.api.v1.auth import require_internal_admin
from app.db.session import get_db
from app.schemas.customer_ops import CustomerCompanyCreate
from app.services.customer_delivery_service import (
    generate_test_bundle_for_customer,
    bundle_download_headers,
    log_bundle_download,
)
from app.repositories.customer_delivery_repository import get_customer_by_id
from app.services.customer_ops_service import (
    confirm_customer_setup_slot,
    create_customer,
    force_activate_subscription,
    generate_customer_password_reset_link,
    get_customer_ops_item,
    list_customer_ops_notifications,
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


class PasswordResetLinkResponse(BaseModel):
    status: str
    customer_id: str
    tenant_code: Optional[str] = None
    company_name: Optional[str] = None
    email: str
    reset_url: str
    token_hint: Optional[str] = None
    expires_at: Optional[str] = None
    expires_minutes: int
    source: str
    safety: dict


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


@router.get("/notifications")
def list_notifications_route(
    limit: int = Query(default=20, ge=1, le=100),
    _: dict = Depends(require_internal_admin),
):
    try:
        return list_customer_ops_notifications(limit=limit)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_ops_notifications_failed: {exc}")


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


@router.post("/customers/{customer_id}/password-reset-link", response_model=PasswordResetLinkResponse)
def create_customer_password_reset_link_route(
    customer_id: str,
    current_user: dict = Depends(require_internal_admin),
    db: Session = Depends(get_db),
):
    try:
        return generate_customer_password_reset_link(
            db,
            customer_id,
            created_by_user_id=str(current_user.get("id") or ""),
        )
    except ValueError as exc:
        msg = str(exc)
        if "customer_not_found" in msg:
            raise HTTPException(status_code=404, detail=msg)
        if "customer_password_reset_email_missing" in msg or "customer_password_reset_user_not_found" in msg:
            raise HTTPException(status_code=409, detail=msg)
        raise HTTPException(status_code=400, detail=msg)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_password_reset_link_failed: {exc}")


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


@router.get("/customers/{customer_id}/download-bundle")
def download_test_bundle_route(
    customer_id: str,
    _: dict = Depends(require_internal_admin),
):
    """Genera e scarica un bundle personalizzato per il cliente indicato.
    Bypassa il gate pagamento/slot — solo per uso interno/test."""
    try:
        bundle = generate_test_bundle_for_customer(customer_id)
        customer_profile = get_customer_by_id(customer_id)
        log_bundle_download(actor="customer_ops", customer_profile=customer_profile, bundle=bundle)
        return FileResponse(
            path=bundle["bundle_path"],
            filename=bundle["filename"],
            media_type="application/octet-stream",
            headers=bundle_download_headers(bundle),
        )
    except RuntimeError as exc:
        msg = str(exc)
        if "customer_not_found" in msg:
            raise HTTPException(status_code=404, detail=msg)
        raise HTTPException(status_code=500, detail=f"generate_test_bundle_failed: {exc}")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"generate_test_bundle_failed: {exc}")


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
