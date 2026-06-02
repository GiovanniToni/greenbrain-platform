from __future__ import annotations

from typing import Any, Dict, Optional
from datetime import datetime, timezone

from app.integrations.supabase_client import get_supabase_client


def get_customer_by_tenant_code(tenant_code: str) -> Optional[Dict[str, Any]]:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_companies")
        .select("customer_id,tenant_code,company_name,installed_release_version")
        .eq("tenant_code", tenant_code)
        .limit(1)
        .execute()
    )
    rows = resp.data or []
    return rows[0] if rows else None


def upsert_tenant(payload: Dict[str, Any]) -> Dict[str, Any]:
    client = get_supabase_client()
    resp = (
        client.table("greenbrain_tenants")
        .upsert(payload, on_conflict="tenant_code")
        .execute()
    )
    rows = resp.data or []
    return rows[0] if rows else payload


def upsert_runtime_connection(payload: Dict[str, Any]) -> Dict[str, Any]:
    client = get_supabase_client()
    resp = (
        client.table("greenbrain_runtime_connections")
        .upsert(payload, on_conflict="tenant_code")
        .execute()
    )
    rows = resp.data or []
    return rows[0] if rows else payload


def upsert_runtime_installation(payload: Dict[str, Any]) -> Dict[str, Any]:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_runtime_installations")
        .upsert(payload, on_conflict="installation_id")
        .execute()
    )
    rows = resp.data or []
    return rows[0] if rows else payload


def update_customer_runtime_fields(customer_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_companies")
        .update(payload)
        .eq("customer_id", customer_id)
        .execute()
    )
    rows = resp.data or []
    return rows[0] if rows else payload


def get_runtime_status_by_tenant(tenant_code: str) -> Dict[str, Any]:
    client = get_supabase_client()

    tenant_resp = (
        client.table("greenbrain_tenants")
        .select("*")
        .eq("tenant_code", tenant_code)
        .limit(1)
        .execute()
    )

    conn_resp = (
        client.table("greenbrain_runtime_connections")
        .select("*")
        .eq("tenant_code", tenant_code)
        .limit(1)
        .execute()
    )

    inst_resp = (
        client.table("gb_customer_runtime_installations")
        .select("*")
        .eq("tenant_code", tenant_code)
        .order("last_heartbeat_at", desc=True)
        .limit(10)
        .execute()
    )

    return {
        "tenant": (tenant_resp.data or [None])[0],
        "runtime_connection": (conn_resp.data or [None])[0],
        "installations": inst_resp.data or [],
    }


def insert_runtime_token(payload: Dict[str, Any]) -> Dict[str, Any]:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_runtime_provisioning_tokens")
        .insert(payload)
        .execute()
    )
    rows = resp.data or []
    if not rows:
        raise RuntimeError("runtime_token_insert_failed")
    return rows[0]


def get_active_runtime_token_by_hash(token_hash: str) -> Optional[Dict[str, Any]]:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_runtime_provisioning_tokens")
        .select("*")
        .eq("token_hash", token_hash)
        .eq("status", "active")
        .limit(1)
        .execute()
    )
    rows = resp.data or []
    return rows[0] if rows else None


def get_runtime_token_by_hash(token_hash: str) -> Optional[Dict[str, Any]]:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_runtime_provisioning_tokens")
        .select("*")
        .eq("token_hash", token_hash)
        .in_("status", ["active", "used"])
        .limit(1)
        .execute()
    )
    rows = resp.data or []
    return rows[0] if rows else None


def mark_runtime_token_used(token_id: str, installation_id: str, used_at: str) -> Dict[str, Any]:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_runtime_provisioning_tokens")
        .update({
            "status": "used",
            "used_at": used_at,
            "used_by_installation_id": installation_id,
        })
        .eq("token_id", token_id)
        .execute()
    )
    rows = resp.data or []
    return rows[0] if rows else {"token_id": token_id, "status": "used"}


def get_active_runtime_token_by_customer(customer_id: str, tenant_code: str) -> Dict[str, Any] | None:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_runtime_provisioning_tokens")
        .select("*")
        .eq("customer_id", customer_id)
        .eq("tenant_code", tenant_code)
        .eq("status", "active")
        .order("created_at", desc=True)
        .limit(1)
        .execute()
    )
    rows = resp.data or []
    return rows[0] if rows else None


def revoke_active_runtime_tokens_by_customer(customer_id: str, tenant_code: str) -> list[Dict[str, Any]]:
    client = get_supabase_client()
    resp = (
        client.table("gb_customer_runtime_provisioning_tokens")
        .update({"status": "revoked"})
        .eq("customer_id", customer_id)
        .eq("tenant_code", tenant_code)
        .eq("status", "active")
        .execute()
    )
    return resp.data or []



def get_pending_password_sync_for_runtime(tenant_code: str) -> Optional[Dict[str, Any]]:
    client = get_supabase_client()
    resp = (
        client.table("greenbrain_users")
        .select(
            "id,email,tenant_code,hashed_password,password_changed_at,"
            "password_change_source,password_version,password_sync_required_at,"
            "password_last_synced_at,password_last_sync_status,password_last_sync_error"
        )
        .eq("tenant_code", tenant_code)
        .eq("password_last_sync_status", "pending")
        .order("password_sync_required_at", desc=True)
        .limit(1)
        .execute()
    )
    rows = resp.data or []
    return rows[0] if rows else None


def ack_password_sync_for_runtime(
    *,
    user_id: str,
    tenant_code: str,
    password_version: int,
    status: str,
    error: str | None = None,
) -> Dict[str, Any]:
    client = get_supabase_client()
    now_iso = datetime.now(timezone.utc).replace(microsecond=0).isoformat()

    update_payload: Dict[str, Any] = {
        "password_last_sync_attempt_at": now_iso,
        "password_last_sync_status": status,
        "password_last_sync_error": error,
    }

    if status == "synced":
        update_payload["password_last_synced_at"] = now_iso
        update_payload["password_last_sync_error"] = None

    resp = (
        client.table("greenbrain_users")
        .update(update_payload)
        .eq("id", user_id)
        .eq("tenant_code", tenant_code)
        .eq("password_version", password_version)
        .execute()
    )
    rows = resp.data or []
    updated = rows[0] if rows else {
        "id": user_id,
        "tenant_code": tenant_code,
        "password_version": password_version,
        "password_last_sync_status": status,
        "password_last_sync_error": error,
    }

    event_resp = (
        client.table("greenbrain_user_password_events")
        .insert({
            "user_id": user_id,
            "email": updated.get("email") or "",
            "tenant_code": tenant_code,
            "event_type": "password_sync_ack",
            "source": "customer_runtime",
            "status": status,
            "password_version": password_version,
            "details": {
                "sync_status": status,
                "error": error,
            },
        })
        .execute()
    )

    return {
        "user": updated,
        "event": (event_resp.data or [None])[0],
    }
