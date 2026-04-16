from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict

from app.repositories.customer_delivery_repository import (
    get_customer_by_id,
    mark_bundle_sent,
)


def prepare_delivery_plan(customer_id: str) -> Dict[str, Any]:
    customer = get_customer_by_id(customer_id)

    assigned_release_version = (customer.get("assigned_release_version") or "").strip()
    if not assigned_release_version:
        raise RuntimeError("assigned_release_version_missing")

    tenant_code = (customer.get("tenant_code") or "").strip()
    company_name = (customer.get("company_name") or "").strip()

    return {
        "status": "planned",
        "customer_id": customer_id,
        "tenant_code": tenant_code,
        "company_name": company_name,
        "assigned_release_version": assigned_release_version,
        "message": "Bundle generation must run on host via tools/customer_ops/prepare_assigned_bundle.sh",
    }


def mark_delivery_sent(customer_id: str) -> Dict[str, Any]:
    ts = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    row = mark_bundle_sent(customer_id=customer_id, bundle_sent_at=ts)
    return {
        "status": "sent_marked",
        "customer_id": customer_id,
        "bundle_sent_at": row.get("bundle_sent_at", ts),
        "delivery": row,
    }
