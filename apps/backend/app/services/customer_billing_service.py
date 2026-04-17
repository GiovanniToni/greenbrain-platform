from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Dict

import stripe

from app.repositories.customer_subscription_repository import (
    get_customer_company,
    get_customer_company_by_portal_email,
    update_customer_company_subscription_fields,
    upsert_customer_subscription,
)


def _required_env(name: str) -> str:
    value = (os.getenv(name) or "").strip()
    if not value:
        raise RuntimeError(f"missing_env:{name}")
    return value


def _iso_from_unix(ts: int | None) -> str | None:
    if not ts:
        return None
    return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()


def _init_stripe() -> None:
    stripe.api_key = _required_env("STRIPE_SECRET_KEY")


def create_checkout_session_for_customer(customer_id: str) -> Dict[str, str]:
    _init_stripe()

    app_base_url = _required_env("APP_BASE_URL")
    price_id = _required_env("STRIPE_PRICE_STARTER_MONTHLY")

    customer = get_customer_company(customer_id)
    if not customer:
        raise RuntimeError(f"customer_not_found:{customer_id}")

    email = (customer.get("portal_user_email") or customer.get("contact_email") or "").strip()
    if not email:
        raise RuntimeError("customer_email_missing")

    session = stripe.checkout.Session.create(
        mode="subscription",
        customer_email=email,
        line_items=[{"price": price_id, "quantity": 1}],
        success_url=f"{app_base_url}/account?billing=success",
        cancel_url=f"{app_base_url}/account?billing=cancel",
        metadata={
            "customer_id": customer_id,
            "tenant_code": customer.get("tenant_code") or "",
        },
    )

    now_iso = datetime.now(timezone.utc).isoformat()

    upsert_customer_subscription({
        "customer_id": customer_id,
        "provider": "stripe",
        "plan_code": price_id,
        "billing_email": email,
        "subscription_status": "checkout_started",
        "stripe_checkout_session_id": session.id,
        "updated_at": now_iso,
    })

    update_customer_company_subscription_fields(customer_id, {
        "subscription_status": "checkout_started",
        "billing_email": email,
        "updated_at": now_iso,
    })

    return {
        "status": "checkout_created",
        "customer_id": customer_id,
        "checkout_url": session.url,
        "checkout_session_id": session.id,
    }


def create_checkout_session_for_portal_email(user_email: str) -> Dict[str, str]:
    customer = get_customer_company_by_portal_email(user_email)
    if not customer:
        raise RuntimeError(f"customer_not_found_for_email:{user_email}")
    return create_checkout_session_for_customer(customer["customer_id"])


def handle_stripe_webhook(payload: bytes, signature: str) -> Dict[str, str]:
    _init_stripe()
    webhook_secret = _required_env("STRIPE_WEBHOOK_SECRET")

    event = stripe.Webhook.construct_event(payload, signature, webhook_secret)
    event_type = event["type"]
    obj = event["data"]["object"]

    if event_type == "checkout.session.completed":
        customer_id = ((obj.get("metadata") or {}).get("customer_id") or "").strip()
        if customer_id:
            now_iso = datetime.now(timezone.utc).isoformat()

            update_customer_company_subscription_fields(customer_id, {
                "subscription_status": "checkout_completed",
                "stripe_customer_id": obj.get("customer"),
                "stripe_subscription_id": obj.get("subscription"),
                "billing_email": (obj.get("customer_details") or {}).get("email"),
                "updated_at": now_iso,
            })

            upsert_customer_subscription({
                "customer_id": customer_id,
                "provider": "stripe",
                "billing_email": (obj.get("customer_details") or {}).get("email"),
                "subscription_status": "checkout_completed",
                "stripe_customer_id": obj.get("customer"),
                "stripe_subscription_id": obj.get("subscription"),
                "stripe_checkout_session_id": obj.get("id"),
                "updated_at": now_iso,
            })

    if event_type in (
        "customer.subscription.created",
        "customer.subscription.updated",
        "customer.subscription.deleted",
    ):
        metadata = obj.get("metadata") or {}
        customer_id = (metadata.get("customer_id") or "").strip()

        if customer_id:
            now_iso = datetime.now(timezone.utc).isoformat()
            status = obj.get("status")

            update_customer_company_subscription_fields(customer_id, {
                "subscription_status": status,
                "stripe_customer_id": obj.get("customer"),
                "stripe_subscription_id": obj.get("id"),
                "updated_at": now_iso,
            })

            upsert_customer_subscription({
                "customer_id": customer_id,
                "provider": "stripe",
                "subscription_status": status,
                "stripe_customer_id": obj.get("customer"),
                "stripe_subscription_id": obj.get("id"),
                "current_period_start": _iso_from_unix(obj.get("current_period_start")),
                "current_period_end": _iso_from_unix(obj.get("current_period_end")),
                "cancel_at_period_end": bool(obj.get("cancel_at_period_end")),
                "updated_at": now_iso,
            })

    return {"status": "ok", "event_type": event_type}
