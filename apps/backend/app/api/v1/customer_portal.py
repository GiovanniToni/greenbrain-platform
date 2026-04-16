from __future__ import annotations

from fastapi import APIRouter, Depends, Header, HTTPException
from fastapi.responses import FileResponse
from jose import JWTError

from app.core.security import decode_token
from app.services.customer_portal_service import build_customer_portal_profile
from app.services.customer_delivery_service import resolve_bundle_download

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


@router.get("/health")
def customer_portal_health():
    return {"status": "ok", "service": "customer-portal"}


@router.get("/me")
def customer_portal_me(email: str = Depends(get_portal_email_from_bearer)):
    try:
        return build_customer_portal_profile(email)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_portal_me_failed: {exc}")


@router.get("/download-bundle")
def customer_portal_download_bundle(email: str = Depends(get_portal_email_from_bearer)):
    try:
        profile = build_customer_portal_profile(email)
        bundle = resolve_bundle_download(profile)

        return FileResponse(
            path=bundle["bundle_path"],
            filename=bundle["filename"],
            media_type="application/gzip",
        )
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"customer_portal_download_bundle_failed: {exc}")
