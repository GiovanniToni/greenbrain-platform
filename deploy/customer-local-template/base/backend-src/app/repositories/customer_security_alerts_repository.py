from __future__ import annotations

import json
import logging
from typing import Any, Dict, List, Optional

from sqlalchemy import text
from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)

ACTIVE_PASSWORD_RESET_ALERT_STATUSES = (
    "open",
    "pending_admin_action",
    "email_sent",
    "email_failed",
    "expired",
    "rate_limited",
)


def _details_json(details: dict[str, Any] | None) -> str:
    return json.dumps(details or {}, ensure_ascii=False, default=str)


def find_customer_by_portal_email(db: Session, email: str) -> Optional[Dict[str, Any]]:
    clean_email = (email or "").lower().strip()
    if not clean_email:
        return None

    row = db.execute(
        text("""
            SELECT
              customer_id,
              tenant_code,
              company_name,
              contact_email,
              portal_user_email,
              billing_email
            FROM public.gb_customer_companies
            WHERE lower(COALESCE(portal_user_email, '')) = lower(:email)
               OR lower(COALESCE(contact_email, '')) = lower(:email)
               OR lower(COALESCE(billing_email, '')) = lower(:email)
            ORDER BY
              CASE
                WHEN lower(COALESCE(portal_user_email, '')) = lower(:email) THEN 0
                WHEN lower(COALESCE(contact_email, '')) = lower(:email) THEN 1
                ELSE 2
              END,
              updated_at DESC NULLS LAST
            LIMIT 1
        """),
        {"email": clean_email},
    ).mappings().first()

    return dict(row) if row else None


def upsert_password_reset_self_service_alert(
    db: Session,
    *,
    email: str,
    customer_id: str | None = None,
    tenant_code: str | None = None,
    status: str = "pending_admin_action",
    severity: str = "warning",
    title: str = "Reset password self-service richiesto",
    message: str = (
        "Il cliente ha richiesto il recupero password dal self-service. "
        "Genera un link di reset manuale dal box Sicurezza account e invialo al cliente."
    ),
    source: str = "self_service",
    details: dict[str, Any] | None = None,
) -> Dict[str, Any]:
    clean_email = (email or "").lower().strip()
    if not clean_email:
        raise ValueError("email_required")

    # Safer than INSERT ... ON CONFLICT on a functional partial index:
    # update existing active alert first, then insert only if none exists.
    row = db.execute(
        text("""
            UPDATE public.greenbrain_customer_security_alerts
            SET
              customer_id = COALESCE(CAST(NULLIF(:customer_id, '') AS uuid), customer_id),
              tenant_code = COALESCE(NULLIF(:tenant_code, ''), tenant_code),
              status = :status,
              severity = :severity,
              title = :title,
              message = :message,
              source = :source,
              last_seen_at = now(),
              resolved_at = NULL,
              details = details || CAST(:details AS jsonb)
            WHERE lower(email) = lower(:email)
              AND alert_type = 'password_reset_self_service'
              AND resolved_at IS NULL
              AND status IN ('open', 'pending_admin_action', 'email_sent', 'email_failed', 'expired', 'rate_limited')
            RETURNING *
        """),
        {
            "customer_id": str(customer_id or ""),
            "tenant_code": tenant_code or "",
            "email": clean_email,
            "status": status,
            "severity": severity,
            "title": title,
            "message": message,
            "source": source,
            "details": _details_json(details),
        },
    ).mappings().first()

    if row:
        db.commit()
        return dict(row)

    row = db.execute(
        text("""
            INSERT INTO public.greenbrain_customer_security_alerts
              (
                customer_id,
                tenant_code,
                email,
                alert_type,
                status,
                severity,
                title,
                message,
                source,
                details
              )
            VALUES
              (
                CAST(NULLIF(:customer_id, '') AS uuid),
                NULLIF(:tenant_code, ''),
                :email,
                'password_reset_self_service',
                :status,
                :severity,
                :title,
                :message,
                :source,
                CAST(:details AS jsonb)
              )
            RETURNING *
        """),
        {
            "customer_id": str(customer_id or ""),
            "tenant_code": tenant_code or "",
            "email": clean_email,
            "status": status,
            "severity": severity,
            "title": title,
            "message": message,
            "source": source,
            "details": _details_json(details),
        },
    ).mappings().first()

    if not row:
        raise ValueError("customer_security_alert_not_created")

    db.commit()
    return dict(row)


def resolve_password_reset_self_service_alert(
    db: Session,
    *,
    email: str,
    details: dict[str, Any] | None = None,
) -> int:
    clean_email = (email or "").lower().strip()
    if not clean_email:
        return 0

    result = db.execute(
        text("""
            UPDATE public.greenbrain_customer_security_alerts
            SET
              status = 'completed',
              severity = 'info',
              title = 'Reset password self-service completato',
              message = 'Il cliente ha completato correttamente il reset password.',
              last_seen_at = now(),
              resolved_at = now(),
              details = details || CAST(:details AS jsonb)
            WHERE lower(email) = lower(:email)
              AND alert_type = 'password_reset_self_service'
              AND resolved_at IS NULL
              AND status IN ('open', 'pending_admin_action', 'email_sent', 'email_failed', 'expired', 'rate_limited')
        """),
        {
            "email": clean_email,
            "details": _details_json(details),
        },
    )
    db.commit()
    return int(result.rowcount or 0)


def list_active_security_alerts_for_customer(
    db: Session,
    *,
    customer_id: str | None,
    email: str | None = None,
    limit: int = 10,
) -> List[Dict[str, Any]]:
    clean_email = (email or "").lower().strip()
    rows = db.execute(
        text("""
            SELECT *
            FROM public.greenbrain_customer_security_alerts
            WHERE resolved_at IS NULL
              AND status IN ('open', 'pending_admin_action', 'email_sent', 'email_failed', 'expired', 'rate_limited')
              AND (
                (NULLIF(:customer_id, '') IS NOT NULL AND customer_id = CAST(NULLIF(:customer_id, '') AS uuid))
                OR
                (NULLIF(:email, '') IS NOT NULL AND lower(email) = lower(:email))
              )
            ORDER BY
              CASE severity
                WHEN 'error' THEN 0
                WHEN 'warning' THEN 1
                ELSE 2
              END,
              last_seen_at DESC
            LIMIT :limit
        """),
        {
            "customer_id": str(customer_id or ""),
            "email": clean_email,
            "limit": int(limit),
        },
    ).mappings().all()

    return [dict(row) for row in rows]


def get_active_password_reset_alert_for_customer(
    db: Session,
    *,
    customer_id: str | None,
    email: str | None = None,
) -> Optional[Dict[str, Any]]:
    for alert in list_active_security_alerts_for_customer(
        db,
        customer_id=customer_id,
        email=email,
        limit=10,
    ):
        if alert.get("alert_type") == "password_reset_self_service":
            return alert
    return None


def list_active_admin_security_notifications(
    db: Session,
    *,
    limit: int = 20,
) -> List[Dict[str, Any]]:
    """
    Return active customer security alerts for the internal admin notification center.

    Current source table is greenbrain_customer_security_alerts.
    Completed/resolved alerts are intentionally excluded from the bell.
    """
    rows = db.execute(
        text("""
            SELECT
              a.id,
              a.customer_id,
              a.tenant_code,
              a.email,
              a.alert_type,
              a.status,
              a.severity,
              a.title,
              a.message,
              a.source,
              a.first_seen_at,
              a.last_seen_at,
              a.resolved_at,
              a.details,
              c.company_name
            FROM public.greenbrain_customer_security_alerts a
            LEFT JOIN public.gb_customer_companies c
              ON c.customer_id = a.customer_id
            WHERE a.resolved_at IS NULL
              AND a.status IN ('open', 'pending_admin_action', 'email_sent', 'email_failed', 'expired', 'rate_limited')
            ORDER BY
              CASE a.severity
                WHEN 'error' THEN 0
                WHEN 'warning' THEN 1
                ELSE 2
              END,
              a.last_seen_at DESC
            LIMIT :limit
        """),
        {"limit": int(limit)},
    ).mappings().all()

    notifications: List[Dict[str, Any]] = []
    for row in rows:
        item = dict(row)
        customer_id = item.get("customer_id")
        item["target_url"] = f"/customers/{customer_id}" if customer_id else "/customers"
        notifications.append(item)

    return notifications


def mark_password_reset_self_service_alert_link_sent_by_admin(
    db: Session,
    *,
    customer_id: str,
    email: str,
    tenant_code: str | None = None,
    admin_user_id: str | None = None,
    details: dict[str, Any] | None = None,
) -> Dict[str, Any]:
    """
    Mark a password reset alert as manually sent by admin.

    If an active alert already exists, update it to email_sent.
    If no active alert exists, create a new admin_manual email_sent alert.
    The alert remains active until the customer actually completes the reset.
    """
    clean_email = (email or "").lower().strip()
    if not clean_email:
        raise ValueError("email_required")

    merged_details = {
        "link_sent_by": "admin_manual",
        "manual_link_sent": True,
        "admin_user_id": admin_user_id,
        **(details or {}),
    }

    return upsert_password_reset_self_service_alert(
        db,
        email=clean_email,
        customer_id=customer_id,
        tenant_code=tenant_code,
        status="email_sent",
        severity="info",
        title="Link reset password inviato",
        message="L'admin ha inviato manualmente il link di reset. In attesa che il cliente completi il cambio password.",
        source="admin_manual",
        details=merged_details,
    )
