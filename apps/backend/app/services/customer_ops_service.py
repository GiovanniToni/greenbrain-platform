from __future__ import annotations

from typing import Any, Dict, List


def list_customers_stub() -> List[Dict[str, Any]]:
    return [
        {
            "customer_id": "stub-customer-1",
            "company_name": "Garden Demo",
            "tenant_code": "garden-demo",
            "contact_email": "demo@garden.local",
            "onboarding_status": "draft",
            "install_status": "not_started",
            "db_integration_status": "not_started",
            "assigned_release_version": "0.1.12",
            "installed_release_version": None,
            "subscription_status": "inactive",
        }
    ]
