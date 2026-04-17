from __future__ import annotations

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from jose import JWTError
from pydantic import BaseModel

from app.core.security import decode_token
from app.services.customer_billing_service import (
    create_checkout_session_for_customer,
    create_checkout_session_for_portal_email,
    handle_stripe_webhook,
)

router = APIRouter(prefix="/api/v1/customer-billing", tags=["customer-billing"])


class CheckoutPayload(BaseModel):
    customer_id: str


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


@router.get("/health")
def customer_billing_health():
    return {"status": "ok", "service": "customer-billing"}


@router.post("/checkout")
def create_checkout(payload: CheckoutPayload):
    try:
        return create_checkout_session_for_customer(payload.customer_id)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_billing_checkout_failed: {exc}")


@router.post("/portal-checkout")
def create_portal_checkout(portal_email: str = Depends(get_portal_email_from_bearer)):
    try:
        return create_checkout_session_for_portal_email(portal_email)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_billing_portal_checkout_failed: {exc}")


@router.post("/webhook")
async def stripe_webhook(request: Request):
    try:
        signature = request.headers.get("stripe-signature", "")
        payload = await request.body()
        return handle_stripe_webhook(payload, signature)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_billing_webhook_failed: {exc}")
