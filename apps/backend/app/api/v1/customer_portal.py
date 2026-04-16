from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse

from app.api.v1.auth import get_current_user
from app.services.customer_portal_service import build_customer_portal_profile
from app.services.customer_delivery_service import resolve_bundle_download

router = APIRouter(prefix="/api/v1/customer-portal", tags=["customer-portal"])


@router.get("/health")
def customer_portal_health():
    return {"status": "ok", "service": "customer-portal"}


@router.get("/me")
def customer_portal_me(current_user=Depends(get_current_user)):
    try:
        email = current_user.get("email") or current_user.get("sub")
        if not email:
            raise RuntimeError("user_email_missing_in_token")
        return build_customer_portal_profile(email)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_portal_me_failed: {exc}")


@router.get("/download-bundle")
def customer_portal_download_bundle(current_user=Depends(get_current_user)):
    try:
        email = current_user.get("email") or current_user.get("sub")
        if not email:
            raise RuntimeError("user_email_missing_in_token")

        profile = build_customer_portal_profile(email)
        bundle = resolve_bundle_download(profile)

        return FileResponse(
            path=bundle["bundle_path"],
            filename=bundle["filename"],
            media_type="application/gzip",
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_portal_download_bundle_failed: {exc}")
