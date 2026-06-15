from __future__ import annotations

from typing import Optional

from fastapi import Request, APIRouter, Depends, Header, HTTPException
from fastapi.responses import FileResponse
from jose import JWTError
from pydantic import BaseModel

from app.core.security import decode_token
from app.services.customer_delivery_service import (
    resolve_bundle_download,
    record_bundle_download,
    bundle_download_headers,
    log_bundle_download,
)
from app.services.customer_portal_service import (
    book_customer_setup_slot,
    build_customer_portal_profile,
    cancel_customer_portal_subscription,
    confirm_customer_data_ok,
    get_customer_source_db_state,
    build_source_db_manager_request,
    parse_source_db_manager_response,
    save_customer_source_db_state,
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



class SourceDbIntegrationPayload(BaseModel):
    db_type: Optional[str] = None
    db_host: Optional[str] = None
    db_port: Optional[int] = None
    db_name: Optional[str] = None
    db_schema: Optional[str] = None
    source_client_code: Optional[str] = None
    db_view_name: Optional[str] = None
    db_username: Optional[str] = None
    password: Optional[str] = None
    db_encrypt: Optional[bool] = None
    db_trust_server_certificate: Optional[bool] = None
    manager_contact_email: Optional[str] = None
    manager_response_raw_text: Optional[str] = None
    notes: Optional[str] = None

@router.get("/health")
def customer_portal_health():
    return {"status": "ok", "service": "customer-portal"}




class SourceDbManagerResponseParsePayload(BaseModel):
    manager_response_raw_text: str


@router.get("/source-db/request-template")
def get_source_db_request_template_route(email: str = Depends(get_portal_email_from_bearer)):
    try:
        return build_source_db_manager_request(email)
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"get_source_db_request_template_failed: {exc}")


@router.post("/source-db/parse-response")
def parse_source_db_response_route(
    payload: SourceDbManagerResponseParsePayload,
    email: str = Depends(get_portal_email_from_bearer),
):
    try:
        return parse_source_db_manager_response(email, payload.model_dump())
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"parse_source_db_response_failed: {exc}")


@router.get("/source-db")
def get_source_db_state_route(email: str = Depends(get_portal_email_from_bearer)):
    try:
        return get_customer_source_db_state(email)
    except RuntimeError as exc:
        msg = str(exc)
        if "customer_portal_profile_not_found" in msg:
            raise HTTPException(status_code=404, detail=msg)
        raise HTTPException(status_code=500, detail=f"get_source_db_state_failed: {exc}")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"get_source_db_state_failed: {exc}")


@router.post("/source-db")
def save_source_db_state_route(
    payload: SourceDbIntegrationPayload,
    email: str = Depends(get_portal_email_from_bearer),
):
    try:
        return save_customer_source_db_state(email, payload.model_dump())
    except RuntimeError as exc:
        msg = str(exc)
        if "customer_portal_profile_not_found" in msg:
            raise HTTPException(status_code=404, detail=msg)
        if "source_db_secret_key" in msg:
            raise HTTPException(status_code=500, detail=msg)
        raise HTTPException(status_code=500, detail=f"save_source_db_state_failed: {exc}")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"save_source_db_state_failed: {exc}")


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
        if "customer_portal_profile_not_found" in msg or "customer_not_found" in msg:
            raise HTTPException(status_code=404, detail=msg)
        raise HTTPException(status_code=500, detail=f"cancel_subscription_failed: {exc}")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"cancel_subscription_failed: {exc}")


@router.get("/download-bundle")
def customer_portal_download_bundle(request: Request, email: str = Depends(get_portal_email_from_bearer)):
    try:
        profile = build_customer_portal_profile(email)
        user_agent = request.headers.get("user-agent", "")
        bundle = resolve_bundle_download(profile, user_agent=user_agent)
        record_bundle_download(profile, bundle)
        log_bundle_download(actor="customer_portal", customer_profile=profile, bundle=bundle)

        return FileResponse(
            path=bundle["bundle_path"],
            filename=bundle["filename"],
            media_type="application/octet-stream",
            headers=bundle_download_headers(bundle),
        )
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_portal_download_bundle_failed: {exc}")
