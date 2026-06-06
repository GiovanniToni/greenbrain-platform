from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import (
    create_access_token,
    decode_token,
    hash_password,
    verify_password,
)
from app.db.session import get_db
from app.db.users import (
    count_users,
    create_admin_user,
    create_user,
    get_user_by_email,
    update_last_login,
    update_user_password_hash,
)
from app.repositories.customer_portal_repository import get_runtime_connection_by_tenant_code
from app.repositories.customer_security_alerts_repository import (
    find_customer_by_portal_email,
    resolve_password_reset_self_service_alert,
    upsert_password_reset_self_service_alert,
)
from app.services.password_reset_service import (
    create_password_reset_for_email,
    reset_password_with_token,
)

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])

_bearer = HTTPBearer()
SSO_ALGORITHM = "HS256"


class LoginRequest(BaseModel):
    email: str
    password: str


class SetupRequest(BaseModel):
    email: str
    password: str
    full_name: str | None = None


class AdminUserCreateRequest(BaseModel):
    email: str
    password: str
    full_name: str | None = None


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int


class UserResponse(BaseModel):
    id: str
    email: str
    full_name: str | None
    is_admin: bool
    tenant_code: str | None = None
    home_host: str | None = None
    home_path: str | None = None
    user_role: str | None = None
    platform_enabled: bool = False
    runtime_health: str | None = None
    runtime_public_backend_url: str | None = None
    runtime_installation_id: str | None = None


class SsoStartResponse(BaseModel):
    redirect_url: str
    target_host: str
    target_path: str


class SsoExchangeRequest(BaseModel):
    ticket: str


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str


class PasswordChangeResponse(BaseModel):
    ok: bool = True
    email: str
    password_changed_at: datetime | None = None
    password_version: int | None = None
    password_last_sync_status: str | None = None
    password_sync_required_at: datetime | None = None


class PasswordResetRequest(BaseModel):
    email: str


class PasswordResetRequestResponse(BaseModel):
    ok: bool = True
    message: str


class PasswordResetConfirmRequest(BaseModel):
    token: str
    new_password: str


class PasswordResetConfirmResponse(BaseModel):
    ok: bool = True
    email: str
    password_changed_at: datetime | None = None
    password_version: int | None = None
    password_last_sync_status: str | None = None
    password_sync_required_at: datetime | None = None


def _build_sso_ticket(user: dict) -> str:
    now = datetime.now(timezone.utc)
    exp = now + timedelta(minutes=2)

    home_host = (user.get("home_host") or "").strip()
    home_path = (user.get("home_path") or "/dashboard").strip() or "/dashboard"

    payload = {
        "sub": user["email"],
        "email": user["email"],
        "full_name": user.get("full_name"),
        "is_admin": bool(user.get("is_admin")),
        "tenant_code": user.get("tenant_code"),
        "home_host": home_host,
        "home_path": home_path,
        "user_role": user.get("user_role"),
        "purpose": "greenbrain_sso",
        "iss": "greenbrain_auth",
        "aud": home_host,
        "exp": exp,
        "iat": now,
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=SSO_ALGORITHM)


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
    db: Session = Depends(get_db),
) -> dict:
    try:
        email = decode_token(credentials.credentials)
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user = get_user_by_email(db, email)
    if not user or not user["is_active"]:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


INTERNAL_ADMIN_ROLES = {"super_admin", "greenbrain_admin"}
PLATFORM_ACCESS_ROLES = {"super_admin", "greenbrain_admin", "customer_admin", "customer_user", "tenant_admin"}


def _user_role(user: dict) -> str:
    return str(user.get("user_role") or "").strip()


def require_admin(user: dict = Depends(get_current_user)) -> dict:
    """Backward-compatible admin guard.

    Kept for existing internal/cloud-only routes.
    Prefer require_internal_admin or require_platform_access for new code.
    """
    if not user.get("is_admin"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required",
        )
    return user


def require_internal_admin(user: dict = Depends(get_current_user)) -> dict:
    """GreenBrain internal admin only: ops, customers, delivery, provisioning."""
    role = _user_role(user)
    if role in INTERNAL_ADMIN_ROLES:
        return user

    # Backward compatibility for old internal admins without user_role.
    if user.get("is_admin") and not user.get("tenant_code"):
        return user

    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Internal admin access required",
    )


def require_platform_access(user: dict = Depends(get_current_user)) -> dict:
    """Operational platform access: dashboards, analytics, catalog, sales, forecast, planner."""
    role = _user_role(user)
    if role in PLATFORM_ACCESS_ROLES:
        return user

    # Backward compatibility for old admin/dev accounts.
    if user.get("is_admin"):
        return user

    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Platform access required",
    )


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, db: Session = Depends(get_db)):
    user = get_user_by_email(db, body.email)
    if not user or not verify_password(body.password, user["hashed_password"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
        )
    if not user["is_active"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account disabled",
        )

    update_last_login(db, str(user["id"]))
    token = create_access_token(subject=user["email"])
    return TokenResponse(
        access_token=token,
        expires_in=settings.jwt_expire_minutes * 60,
    )



@router.post("/request-password-reset", response_model=PasswordResetRequestResponse)
def request_password_reset(
    body: PasswordResetRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    email = (body.email or "").lower().strip()
    if not email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="email_required",
        )

    # Always return a generic response to avoid user enumeration.
    # Current phase: self-service creates an internal admin alert; admin sends the reset link manually.
    try:
        created = create_password_reset_for_email(
            db,
            email=email,
            source="self_service",
            frontend_base_url=None,
            requested_ip=request.client.host if request.client else None,
            requested_user_agent=request.headers.get("user-agent"),
        )

        if created.get("status") == "created":
            try:
                customer = find_customer_by_portal_email(db, created.get("email") or email) or {}
                upsert_password_reset_self_service_alert(
                    db,
                    email=created.get("email") or email,
                    customer_id=customer.get("customer_id"),
                    tenant_code=customer.get("tenant_code"),
                    status="pending_admin_action",
                    severity="warning",
                    title="Reset password self-service richiesto",
                    message=(
                        "Il cliente ha richiesto il recupero password dal self-service. "
                        "Genera un link di reset manuale dal box Sicurezza account e invialo al cliente."
                    ),
                    source="self_service",
                    details={
                        "requested_ip": request.client.host if request.client else None,
                        "requested_user_agent": request.headers.get("user-agent"),
                        "token_created": True,
                        "expires_at": str(created.get("expires_at") or ""),
                        "requires_admin_manual_link": True,
                        "email_delivery": "not_configured",
                    },
                )
            except Exception:
                db.rollback()
                # Public password-reset requests must stay generic and must not fail
                # because an internal admin alert could not be created.
                pass
    except ValueError as exc:
        if str(exc) == "email_required":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="email_required",
            )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="password_reset_request_invalid",
        )

    return PasswordResetRequestResponse(
        message="Se l'email è registrata, potrai ricevere istruzioni per reimpostare la password.",
    )


@router.post("/reset-password", response_model=PasswordResetConfirmResponse)
def reset_password(
    body: PasswordResetConfirmRequest,
    db: Session = Depends(get_db),
):
    token = (body.token or "").strip()
    new_password = body.new_password or ""

    if not token:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="reset_token_required",
        )

    try:
        updated = reset_password_with_token(
            db,
            raw_token=token,
            new_password=new_password,
        )
    except ValueError as exc:
        detail = str(exc)
        if detail in {
            "reset_token_required",
            "new_password_too_short",
            "new_password_same_as_current",
            "password_reset_token_invalid_or_expired",
            "password_reset_token_user_missing",
        }:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=detail,
            )
        if detail == "password_reset_user_inactive":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=detail,
            )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="password_reset_failed",
        )

    try:
        resolve_password_reset_self_service_alert(
            db,
            email=updated["email"],
            details={
                "resolved_by": "password_reset_completed",
                "password_version": updated.get("password_version"),
                "token_used_at": str(updated.get("token_used_at") or ""),
            },
        )
    except Exception:
        db.rollback()
        # Password reset must not fail because an internal ops alert could not be resolved.
        pass

    return PasswordResetConfirmResponse(
        email=updated["email"],
        password_changed_at=updated.get("password_changed_at"),
        password_version=updated.get("password_version"),
        password_last_sync_status=updated.get("password_last_sync_status"),
        password_sync_required_at=updated.get("password_sync_required_at"),
    )


@router.post("/change-password", response_model=PasswordChangeResponse)
def change_password(
    body: ChangePasswordRequest,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    current_password = (body.current_password or "").strip()
    new_password = body.new_password or ""

    if not current_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="current_password_required",
        )

    if not verify_password(current_password, current_user["hashed_password"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid_current_password",
        )

    if len(new_password) < 8:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="new_password_too_short",
        )

    if verify_password(new_password, current_user["hashed_password"]):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="new_password_same_as_current",
        )

    updated = update_user_password_hash(
        db,
        user_id=str(current_user["id"]),
        hashed_password=hash_password(new_password),
        changed_by_user_id=str(current_user["id"]),
        source="cloud_api",
    )

    return PasswordChangeResponse(
        email=updated["email"],
        password_changed_at=updated.get("password_changed_at"),
        password_version=updated.get("password_version"),
        password_last_sync_status=updated.get("password_last_sync_status"),
        password_sync_required_at=updated.get("password_sync_required_at"),
    )


@router.post("/sso/start", response_model=SsoStartResponse)
def sso_start(body: LoginRequest, db: Session = Depends(get_db)):
    user = get_user_by_email(db, body.email)
    if not user or not verify_password(body.password, user["hashed_password"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
        )
    if not user["is_active"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account disabled",
        )

    home_host = (user.get("home_host") or "").strip()
    home_path = (user.get("home_path") or "/dashboard").strip() or "/dashboard"

    if not home_host:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing home_host for user",
        )

    if home_host in {"www.greenbrain.it", "greenbrain.it"}:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="SSO not required for same-cloud user",
        )

    ticket = _build_sso_ticket(user)
    redirect_url = f"https://{home_host}/login?sso={ticket}"

    return SsoStartResponse(
        redirect_url=redirect_url,
        target_host=home_host,
        target_path=home_path,
    )



@router.post("/sso/exchange", response_model=TokenResponse)
def sso_exchange(body: SsoExchangeRequest, request: Request, db: Session = Depends(get_db)):
    try:
        unverified = jwt.get_unverified_claims(body.ticket)
        expected_audience = unverified.get("aud")
        payload = jwt.decode(
            body.ticket,
            settings.jwt_secret,
            algorithms=[SSO_ALGORITHM],
            audience=expected_audience,
        )
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid SSO ticket",
        )

    if payload.get("purpose") != "greenbrain_sso":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid SSO ticket",
        )

    email = (payload.get("email") or "").strip().lower()
    if not email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid SSO ticket",
        )

    user = get_user_by_email(db, email)
    if not user or not user["is_active"]:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not enabled on tenant",
        )

    update_last_login(db, str(user["id"]))
    token = create_access_token(subject=user["email"])
    return TokenResponse(
        access_token=token,
        expires_in=settings.jwt_expire_minutes * 60,
    )

@router.get("/me", response_model=UserResponse)
def me(user: dict = Depends(get_current_user)):
    tenant_code = (user.get("tenant_code") or "").strip()
    runtime = None
    if tenant_code:
        try:
            runtime = get_runtime_connection_by_tenant_code(tenant_code)
        except RuntimeError as exc:
            if "Supabase is not configured" not in str(exc):
                raise
        except Exception:
            runtime = None
    runtime = runtime or {}

    role = _user_role(user)
    is_internal = role in INTERNAL_ADMIN_ROLES or bool(user.get("is_admin") and not user.get("tenant_code"))
    local_access_enabled = bool(user.get("can_access_app"))
    local_home_host = user.get("home_host")

    runtime_health = runtime.get("runtime_health") or ("healthy" if local_access_enabled else None)
    runtime_public_backend_url = runtime.get("public_backend_url") or local_home_host
    runtime_installation_id = runtime.get("installation_id")

    platform_enabled = bool(
        is_internal
        or local_access_enabled
        or (
            runtime_health == "healthy"
            and runtime_public_backend_url
            and runtime_installation_id
        )
    )

    home_path = user.get("home_path")
    if platform_enabled and role in {"customer_admin", "customer_user", "tenant_admin"} and (not home_path or home_path == "/account"):
        home_path = "/dashboard"

    return UserResponse(
        id=str(user["id"]),
        email=user["email"],
        full_name=user.get("full_name"),
        is_admin=bool(user["is_admin"]),
        tenant_code=user.get("tenant_code"),
        home_host=user.get("home_host"),
        home_path=home_path,
        user_role=user.get("user_role"),
        platform_enabled=platform_enabled,
        runtime_health=runtime_health,
        runtime_public_backend_url=runtime_public_backend_url,
        runtime_installation_id=runtime_installation_id,
    )


@router.post(
    "/setup",
    status_code=status.HTTP_201_CREATED,
    response_model=UserResponse,
)
def setup(body: SetupRequest, db: Session = Depends(get_db)):
    if count_users(db) > 0:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Setup already completed",
        )

    user = create_user(
        db,
        email=body.email,
        hashed_password=hash_password(body.password),
        full_name=body.full_name,
        is_admin=True,
    )

    return UserResponse(
        id=str(user["id"]),
        email=user["email"],
        full_name=user.get("full_name"),
        is_admin=bool(user["is_admin"]),
        tenant_code=user.get("tenant_code"),
        home_host=user.get("home_host"),
        home_path=user.get("home_path"),
        user_role=user.get("user_role"),
    )


@router.post("/admin-users", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def create_admin_user_route(
    body: AdminUserCreateRequest,
    _: dict = Depends(require_admin),
    db: Session = Depends(get_db),
):
    email = body.email.lower().strip()
    if get_user_by_email(db, email):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="User already exists",
        )

    if len(body.password) < 8:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must be at least 8 characters",
        )

    user = create_admin_user(
        db,
        email=email,
        hashed_password=hash_password(body.password),
        full_name=body.full_name,
    )

    return UserResponse(
        id=str(user["id"]),
        email=user["email"],
        full_name=user.get("full_name"),
        is_admin=bool(user["is_admin"]),
        tenant_code=user.get("tenant_code"),
        home_host=user.get("home_host"),
        home_path=user.get("home_path"),
        user_role=user.get("user_role"),
    )
