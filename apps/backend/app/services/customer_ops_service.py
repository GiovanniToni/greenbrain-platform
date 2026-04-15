from __future__ import annotations

from typing import Any, Dict, List

from app.repositories.customer_ops_repository import list_customer_companies


def list_customers(limit: int = 100) -> List[Dict[str, Any]]:
    return list_customer_companies(limit=limit)
