#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import text

from app.db.session import SessionLocal


TOKEN_TABLE = "gb_customer_runtime_provisioning_tokens"
INSTALLATION_TABLE = "gb_customer_runtime_installations"


def _json_default(value: Any) -> str:
    if isinstance(value, datetime):
        return value.isoformat()
    return str(value)


def _row_to_dict(row: Any) -> dict[str, Any]:
    return dict(row)


def _require_tenant(tenant: str | None) -> str:
    tenant = (tenant or "").strip()
    if not tenant:
        raise SystemExit("ERROR: --tenant is required")
    return tenant


def _table_exists(db, table_name: str) -> bool:
    return bool(
        db.execute(
            text(
                """
                SELECT EXISTS (
                    SELECT 1
                    FROM information_schema.tables
                    WHERE table_schema = 'public'
                      AND table_name = :table_name
                )
                """
            ),
            {"table_name": table_name},
        ).scalar()
    )


def _print_json(payload: Any) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2, default=_json_default))


def _fetch_tokens(db, tenant: str, limit: int) -> list[dict[str, Any]]:
    rows = db.execute(
        text(
            f"""
            SELECT
                token_id,
                customer_id,
                tenant_code,
                token_hint,
                purpose,
                status,
                expires_at,
                used_at,
                used_by_installation_id,
                created_at,
                updated_at
            FROM public.{TOKEN_TABLE}
            WHERE tenant_code = :tenant
            ORDER BY created_at DESC
            LIMIT :limit
            """
        ),
        {"tenant": tenant, "limit": limit},
    ).mappings().all()
    return [_row_to_dict(row) for row in rows]


def _fetch_installations(db, tenant: str, limit: int) -> list[dict[str, Any]]:
    rows = db.execute(
        text(
            f"""
            SELECT
                installation_id,
                customer_id,
                tenant_code,
                installation_label,
                runtime_mode,
                connection_mode,
                data_mode,
                installed_release_version,
                local_agent_version,
                public_backend_url,
                provisioning_status,
                runtime_health,
                last_heartbeat_at,
                last_sync_at,
                last_sync_status,
                notes,
                created_at,
                updated_at
            FROM public.{INSTALLATION_TABLE}
            WHERE tenant_code = :tenant
            ORDER BY created_at DESC
            LIMIT :limit
            """
        ),
        {"tenant": tenant, "limit": limit},
    ).mappings().all()
    return [_row_to_dict(row) for row in rows]


def command_summary(args: argparse.Namespace) -> int:
    tenant = _require_tenant(args.tenant)

    with SessionLocal() as db:
        missing = [
            table
            for table in (TOKEN_TABLE, INSTALLATION_TABLE)
            if not _table_exists(db, table)
        ]
        if missing:
            _print_json({"status": "error", "missing_tables": missing})
            return 2

        token_rows = db.execute(
            text(
                f"""
                SELECT status, count(*) AS count
                FROM public.{TOKEN_TABLE}
                WHERE tenant_code = :tenant
                GROUP BY status
                ORDER BY count DESC, status
                """
            ),
            {"tenant": tenant},
        ).mappings().all()

        installation_rows = db.execute(
            text(
                f"""
                SELECT
                    provisioning_status,
                    runtime_health,
                    installed_release_version,
                    count(*) AS count
                FROM public.{INSTALLATION_TABLE}
                WHERE tenant_code = :tenant
                GROUP BY provisioning_status, runtime_health, installed_release_version
                ORDER BY count DESC, installed_release_version DESC NULLS LAST
                """
            ),
            {"tenant": tenant},
        ).mappings().all()

        latest_installation = db.execute(
            text(
                f"""
                SELECT
                    installation_id,
                    installed_release_version,
                    local_agent_version,
                    provisioning_status,
                    runtime_health,
                    last_heartbeat_at,
                    created_at,
                    updated_at
                FROM public.{INSTALLATION_TABLE}
                WHERE tenant_code = :tenant
                ORDER BY last_heartbeat_at DESC NULLS LAST, created_at DESC
                LIMIT 1
                """
            ),
            {"tenant": tenant},
        ).mappings().first()

        latest_token = db.execute(
            text(
                f"""
                SELECT
                    token_id,
                    token_hint,
                    status,
                    expires_at,
                    used_at,
                    used_by_installation_id,
                    created_at,
                    updated_at
                FROM public.{TOKEN_TABLE}
                WHERE tenant_code = :tenant
                ORDER BY created_at DESC
                LIMIT 1
                """
            ),
            {"tenant": tenant},
        ).mappings().first()

        payload = {
            "status": "ok",
            "mode": "read_only",
            "tenant_code": tenant,
            "tables": {
                TOKEN_TABLE: "present",
                INSTALLATION_TABLE: "present",
            },
            "token_status_counts": [_row_to_dict(row) for row in token_rows],
            "installation_counts": [_row_to_dict(row) for row in installation_rows],
            "latest_installation_by_heartbeat": _row_to_dict(latest_installation) if latest_installation else None,
            "latest_token_by_created_at": _row_to_dict(latest_token) if latest_token else None,
            "safety": {
                "mutations_enabled": False,
                "updates": 0,
                "deletes": 0,
                "revokes": 0,
                "archives": 0,
            },
        }
        _print_json(payload)
        return 0


def command_list_tokens(args: argparse.Namespace) -> int:
    tenant = _require_tenant(args.tenant)
    limit = max(1, min(int(args.limit), 500))

    with SessionLocal() as db:
        if not _table_exists(db, TOKEN_TABLE):
            _print_json({"status": "error", "missing_table": TOKEN_TABLE})
            return 2

        rows = _fetch_tokens(db, tenant, limit)
        counts = Counter(row.get("status") for row in rows)

        _print_json(
            {
                "status": "ok",
                "mode": "read_only",
                "tenant_code": tenant,
                "limit": limit,
                "returned": len(rows),
                "status_counts_in_returned_rows": dict(counts),
                "tokens": rows,
                "safety": {
                    "mutations_enabled": False,
                    "token_hash_exposed": False,
                    "updates": 0,
                    "deletes": 0,
                    "revokes": 0,
                },
            }
        )
        return 0


def command_list_installations(args: argparse.Namespace) -> int:
    tenant = _require_tenant(args.tenant)
    limit = max(1, min(int(args.limit), 500))

    with SessionLocal() as db:
        if not _table_exists(db, INSTALLATION_TABLE):
            _print_json({"status": "error", "missing_table": INSTALLATION_TABLE})
            return 2

        rows = _fetch_installations(db, tenant, limit)
        health_counts = Counter(row.get("runtime_health") for row in rows)
        version_counts = Counter(row.get("installed_release_version") for row in rows)

        _print_json(
            {
                "status": "ok",
                "mode": "read_only",
                "tenant_code": tenant,
                "limit": limit,
                "returned": len(rows),
                "runtime_health_counts_in_returned_rows": dict(health_counts),
                "installed_release_version_counts_in_returned_rows": dict(version_counts),
                "installations": rows,
                "safety": {
                    "mutations_enabled": False,
                    "updates": 0,
                    "deletes": 0,
                    "archives": 0,
                },
            }
        )
        return 0


def command_cleanup_plan(args: argparse.Namespace) -> int:
    tenant = _require_tenant(args.tenant)
    keep_latest_healthy = max(1, min(int(args.keep_latest_healthy), 20))
    limit_candidates = max(1, min(int(args.limit_candidates), 500))

    with SessionLocal() as db:
        missing = [
            table
            for table in (TOKEN_TABLE, INSTALLATION_TABLE)
            if not _table_exists(db, table)
        ]
        if missing:
            _print_json({"status": "error", "missing_tables": missing})
            return 2

        token_status_rows = db.execute(
            text(
                f"""
                SELECT status, count(*) AS count
                FROM public.{TOKEN_TABLE}
                WHERE tenant_code = :tenant
                GROUP BY status
                ORDER BY count DESC, status
                """
            ),
            {"tenant": tenant},
        ).mappings().all()

        active_tokens = db.execute(
            text(
                f"""
                SELECT
                    token_id,
                    token_hint,
                    purpose,
                    status,
                    expires_at,
                    used_at,
                    used_by_installation_id,
                    created_at,
                    updated_at
                FROM public.{TOKEN_TABLE}
                WHERE tenant_code = :tenant
                  AND status = :active
                ORDER BY created_at DESC
                """
            ),
            {"tenant": tenant, "active": "active"},
        ).mappings().all()

        recent_tokens = db.execute(
            text(
                f"""
                SELECT
                    token_id,
                    token_hint,
                    purpose,
                    status,
                    expires_at,
                    used_at,
                    used_by_installation_id,
                    created_at,
                    updated_at
                FROM public.{TOKEN_TABLE}
                WHERE tenant_code = :tenant
                ORDER BY created_at DESC
                LIMIT 20
                """
            ),
            {"tenant": tenant},
        ).mappings().all()

        ranked_installations = db.execute(
            text(
                f"""
                WITH ranked AS (
                    SELECT
                        installation_id,
                        customer_id,
                        tenant_code,
                        installation_label,
                        runtime_mode,
                        connection_mode,
                        data_mode,
                        installed_release_version,
                        local_agent_version,
                        public_backend_url,
                        provisioning_status,
                        runtime_health,
                        last_heartbeat_at,
                        last_sync_at,
                        last_sync_status,
                        notes,
                        created_at,
                        updated_at,
                        row_number() OVER (
                            ORDER BY last_heartbeat_at DESC NULLS LAST, created_at DESC
                        ) AS heartbeat_rank
                    FROM public.{INSTALLATION_TABLE}
                    WHERE tenant_code = :tenant
                      AND runtime_health = :healthy
                )
                SELECT *
                FROM ranked
                ORDER BY heartbeat_rank
                LIMIT :limit
                """
            ),
            {"tenant": tenant, "healthy": "healthy", "limit": keep_latest_healthy + limit_candidates},
        ).mappings().all()

        keep_installations = []
        candidate_old_installations = []

        for row in ranked_installations:
            item = _row_to_dict(row)
            rank = int(item.get("heartbeat_rank") or 0)
            if rank <= keep_latest_healthy:
                keep_installations.append(item)
            else:
                candidate_old_installations.append(item)

        installation_counts = db.execute(
            text(
                f"""
                SELECT
                    installed_release_version,
                    runtime_health,
                    provisioning_status,
                    count(*) AS count
                FROM public.{INSTALLATION_TABLE}
                WHERE tenant_code = :tenant
                GROUP BY installed_release_version, runtime_health, provisioning_status
                ORDER BY installed_release_version DESC NULLS LAST, count DESC
                """
            ),
            {"tenant": tenant},
        ).mappings().all()

        payload = {
            "status": "ok",
            "mode": "read_only",
            "plan_only": True,
            "tenant_code": tenant,
            "cleanup_policy": {
                "keep_latest_healthy": keep_latest_healthy,
                "selection_order": "last_heartbeat_at DESC NULLS LAST, created_at DESC",
                "candidate_limit": limit_candidates,
            },
            "schema_capabilities": {
                "archive_columns_present": False,
                "safe_mutation_supported_now": False,
                "reason": "No archived/archived_at/deleted/retired/inactive columns exist on runtime token or installation tables.",
            },
            "token_status_counts": [_row_to_dict(row) for row in token_status_rows],
            "active_tokens_warning": {
                "count": len(active_tokens),
                "tokens": [_row_to_dict(row) for row in active_tokens],
            },
            "recent_tokens": [_row_to_dict(row) for row in recent_tokens],
            "installation_counts": [_row_to_dict(row) for row in installation_counts],
            "keep_installations": keep_installations,
            "candidate_old_installations": candidate_old_installations[:limit_candidates],
            "candidate_old_installation_count_returned": len(candidate_old_installations[:limit_candidates]),
            "recommendation": {
                "next_safe_step": "review_plan_only",
                "do_not_mutate_db_yet": True,
                "future_mutation_requires_schema": "Add explicit archived/archived_at or retired/retired_at fields before implementing archive actions.",
            },
            "safety": {
                "mutations_enabled": False,
                "plan_only": True,
                "updates": 0,
                "deletes": 0,
                "revokes": 0,
                "archives": 0,
                "token_hash_exposed": False,
            },
        }
        _print_json(payload)
        return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Read-only customer-local runtime/token ops utility."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_summary = sub.add_parser("summary", help="Show read-only tenant runtime/token summary.")
    p_summary.add_argument("--tenant", required=True)
    p_summary.set_defaults(func=command_summary)

    p_tokens = sub.add_parser("list-tokens", help="List provisioning tokens for a tenant.")
    p_tokens.add_argument("--tenant", required=True)
    p_tokens.add_argument("--limit", type=int, default=50)
    p_tokens.set_defaults(func=command_list_tokens)

    p_inst = sub.add_parser("list-installations", help="List runtime installations for a tenant.")
    p_inst.add_argument("--tenant", required=True)
    p_inst.add_argument("--limit", type=int, default=50)
    p_inst.set_defaults(func=command_list_installations)

    p_plan = sub.add_parser("cleanup-plan", help="Show read-only cleanup candidates without changing data.")
    p_plan.add_argument("--tenant", required=True)
    p_plan.add_argument("--keep-latest-healthy", type=int, default=1)
    p_plan.add_argument("--limit-candidates", type=int, default=50)
    p_plan.set_defaults(func=command_cleanup_plan)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    unsupported_mutation_flags = ["apply", "delete", "revoke", "archive"]
    raw_args = " ".join(sys.argv[1:]).lower()
    for flag in unsupported_mutation_flags:
        if f"--{flag}" in raw_args:
            print(
                f"ERROR: mutation flag --{flag} is not supported by this read-only utility",
                file=sys.stderr,
            )
            return 2

    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
