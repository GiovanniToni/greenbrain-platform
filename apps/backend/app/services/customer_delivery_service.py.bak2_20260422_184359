from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Tuple

from app.repositories.customer_delivery_repository import (
    get_customer_by_id,
    get_delivery_row,
    mark_bundle_sent,
)

RELEASES_ROOT = Path("/opt/greenbrain-platform/releases/customer-local")


def _version_key(version_name: str) -> Tuple[int, ...]:
    parts = []
    for chunk in version_name.split("."):
        try:
            parts.append(int(chunk))
        except ValueError:
            parts.append(0)
    return tuple(parts)


def _find_latest_release_bundle() -> Path | None:
    if not RELEASES_ROOT.exists() or not RELEASES_ROOT.is_dir():
        return None

    candidates: list[tuple[Tuple[int, ...], Path]] = []

    for entry in RELEASES_ROOT.iterdir():
        if not entry.is_dir():
            continue

        version = entry.name.strip()
        bundle = entry / f"customer-local-{version}.tar.gz"
        if bundle.exists() and bundle.is_file():
            candidates.append((_version_key(version), bundle))

    if not candidates:
        return None

    candidates.sort(key=lambda item: item[0], reverse=True)
    return candidates[0][1]


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
    delivery = get_delivery_row(customer_id)
    if not delivery:
        raise ValueError("delivery_row_missing")
    if not delivery.get("bundle_generated_at"):
        raise ValueError("bundle_not_generated_yet")

    ts = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    row = mark_bundle_sent(customer_id=customer_id, bundle_sent_at=ts)
    return {
        "status": "sent_marked",
        "customer_id": customer_id,
        "bundle_sent_at": row.get("bundle_sent_at", ts),
        "delivery": row,
    }


def resolve_bundle_download(customer_profile: Dict[str, Any]) -> Dict[str, Any]:
    payment_saved = customer_profile.get("payment_method_saved") is True
    slot_requested = bool(customer_profile.get("setup_slot_requested_at"))

    if not payment_saved or not slot_requested:
        raise RuntimeError("bundle_not_ready")

    # 1) Preferred source: latest release available on host
    latest_bundle = _find_latest_release_bundle()
    if latest_bundle and latest_bundle.exists() and latest_bundle.is_file():
        return {
            "bundle_path": str(latest_bundle),
            "filename": latest_bundle.name,
            "source": "latest_release",
        }

    # 2) Fallback: per-customer prepared bundle path, if available
    delivery = customer_profile.get("delivery") or {}
    bundle_local_path = (delivery.get("bundle_local_path") or "").strip()
    if bundle_local_path:
        p = Path(bundle_local_path)
        if p.exists() and p.is_file():
            return {
                "bundle_path": str(p),
                "filename": p.name,
                "source": "customer_bundle",
            }
        raise RuntimeError(f"bundle_file_missing: {bundle_local_path}")

    raise RuntimeError("bundle_not_ready")
