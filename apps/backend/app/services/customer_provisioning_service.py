from __future__ import annotations

from typing import Dict


def assign_release_stub(customer_id: str, assigned_release_version: str) -> Dict[str, str]:
    return {
        "customer_id": customer_id,
        "assigned_release_version": assigned_release_version,
        "status": "stub_assigned",
    }
