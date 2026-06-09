from __future__ import annotations

from typing import Any, Dict, Optional

from app.integrations.supabase_client import get_supabase_client


_SOURCE_DB_PUBLIC_SELECT = """
customer_id,
db_type,
db_host,
db_port,
db_name,
db_schema,
source_client_code,
db_view_name,
db_username,
db_password_set,
db_encrypt,
db_trust_server_certificate,
manager_contact_email,
manager_response_raw_text,
manager_response_received_at,
formal_validation_status,
formal_validation_report,
formal_validation_result,
formal_validation_at,
technical_test_status,
technical_test_report,
technical_test_result,
technical_test_at,
last_error_report,
last_error_at,
notes,
created_at,
updated_at
"""


def mask_source_db_integration(row: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """Return a frontend/admin-safe source DB integration payload.

    Never expose db_password_encrypted or checker_token_hash.
    """
    if not row:
        return None

    safe = dict(row)
    safe.pop("db_password_encrypted", None)
    safe.pop("checker_token_hash", None)

    safe["db_password_set"] = bool(safe.get("db_password_set"))
    return safe


def get_source_db_integration(customer_id: str, *, include_secret: bool = False) -> Optional[Dict[str, Any]]:
    client = get_supabase_client()
    select = _SOURCE_DB_PUBLIC_SELECT
    if include_secret:
        select = select + ", db_password_encrypted, checker_token_hash"

    resp = (
        client.table("gb_customer_db_integrations")
        .select(select)
        .eq("customer_id", customer_id)
        .limit(1)
        .execute()
    )
    rows = resp.data or []
    return rows[0] if rows else None


def save_source_db_integration(customer_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    client = get_supabase_client()

    existing = get_source_db_integration(customer_id)
    if existing:
        resp = (
            client.table("gb_customer_db_integrations")
            .update(payload)
            .eq("customer_id", customer_id)
            .execute()
        )
    else:
        insert_payload = dict(payload)
        insert_payload["customer_id"] = customer_id
        resp = (
            client.table("gb_customer_db_integrations")
            .insert(insert_payload)
            .execute()
        )

    rows = resp.data or []
    if not rows:
        raise RuntimeError(f"source_db_integration_save_failed:{customer_id}")

    return rows[0]


def update_customer_db_integration_status(customer_id: str, status: str) -> Dict[str, Any]:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_companies")
        .update({"db_integration_status": status})
        .eq("customer_id", customer_id)
        .execute()
    )
    rows = resp.data or []
    if not rows:
        raise RuntimeError(f"customer_db_integration_status_update_failed:{customer_id}")
    return rows[0]
