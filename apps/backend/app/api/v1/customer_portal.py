from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException
from fastapi.responses import FileResponse
from jose import JWTError
from pydantic import BaseModel

from app.core.security import decode_token
from app.services.customer_delivery_service import (
    resolve_bundle_download,
    record_bundle_download,
)
from app.services.customer_portal_service import (
    book_customer_setup_slot,
    build_customer_portal_profile,
    cancel_customer_portal_subscription,
    confirm_customer_data_ok,
)

router = APIRouter(prefix="/api/v1/customer-portal", tags=["customer-portal"])


def get_portal_email_from_bearer(authorization: str | None = Header(default=None)) -> str:
    if not authorization:
        raise HTTPException(status_code=401, detail="Not authenticated")

    prefix = "bearer "
    if not authorization.lower().startswith(prefix):
        raise HTTPException(status_code=401, detail="Not authenticated")

    token = authorization[len(prefix):].strip()
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    try:
        email = decode_token(token)
    except JWTError:
        raise HTTPException(status_code=401, detail="Not authenticated")

    if not email:
        raise HTTPException(status_code=401, detail="Not authenticated")

    return email


class BookSetupSlotPayload(BaseModel):
    preferred_date: str
    preferred_time: str
    notes: Optional[str] = None


@router.get("/health")
def customer_portal_health():
    return {"status": "ok", "service": "customer-portal"}


@router.get("/me")
def customer_portal_me(email: str = Depends(get_portal_email_from_bearer)):
    try:
        return build_customer_portal_profile(email)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_portal_me_failed: {exc}")


@router.post("/book-setup-slot")
def book_setup_slot(
    payload: BookSetupSlotPayload,
    email: str = Depends(get_portal_email_from_bearer),
):
    try:
        return book_customer_setup_slot(email, payload.model_dump())
    except RuntimeError as exc:
        msg = str(exc)
        if "slot_already_requested" in msg:
            raise HTTPException(status_code=409, detail=msg)
        if "invalid_preferred" in msg:
            raise HTTPException(status_code=400, detail=msg)
        raise HTTPException(status_code=500, detail=f"book_setup_slot_failed: {exc}")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"book_setup_slot_failed: {exc}")


@router.post("/confirm-data-ok")
def confirm_data_ok(email: str = Depends(get_portal_email_from_bearer)):
    try:
        return confirm_customer_data_ok(email)
    except RuntimeError as exc:
        msg = str(exc)
        if "data_not_ready_for_validation" in msg or "payment_method_missing" in msg:
            raise HTTPException(status_code=409, detail=msg)
        raise HTTPException(status_code=500, detail=f"confirm_data_ok_failed: {exc}")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"confirm_data_ok_failed: {exc}")


@router.post("/cancel-subscription")
def cancel_subscription_route(email: str = Depends(get_portal_email_from_bearer)):
    try:
        return cancel_customer_portal_subscription(email)
    except RuntimeError as exc:
        msg = str(exc)
        if "stripe_subscription_id_missing" in msg:
            raise HTTPException(status_code=409, detail=msg)
        if "customer_portal_profile_not_found" in msg or "customer_not_found" in msg:
            raise HTTPException(status_code=404, detail=msg)
        raise HTTPException(status_code=500, detail=f"cancel_subscription_failed: {exc}")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"cancel_subscription_failed: {exc}")


@router.get("/download-bundle")
def customer_portal_download_bundle(email: str = Depends(get_portal_email_from_bearer)):
    try:
        profile = build_customer_portal_profile(email)
        bundle = resolve_bundle_download(profile)
        record_bundle_download(profile, bundle)

        return FileResponse(
            path=bundle["bundle_path"],
            filename=bundle["filename"],
            media_type="application/gzip",
        )
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_portal_download_bundle_failed: {exc}")
