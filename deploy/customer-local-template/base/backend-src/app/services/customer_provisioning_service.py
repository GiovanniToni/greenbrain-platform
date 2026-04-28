from __future__ import annotations

from typing import Any, Dict

from app.repositories.customer_provisioning_repository import assign_release_to_customer


def assign_release(customer_id: str, assigned_release_version: str) -> Dict[str, Any]:
    return assign_release_to_customer(
        customer_id=customer_id,
        assigned_release_version=assigned_release_version,
    )
