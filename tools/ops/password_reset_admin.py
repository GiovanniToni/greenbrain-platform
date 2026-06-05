#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from typing import Any

from sqlalchemy import text

from app.db.session import SessionLocal
from app.services.password_reset_service import create_password_reset_for_email


RESET_TOKEN_TABLE = "greenbrain_user_password_reset_tokens"


def _json_default(value: Any) -> str:
    if isinstance(value, datetime):
        return value.isoformat()
    return str(value)


def _print_json(payload: Any) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2, default=_json_default))


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


def _require_email(email: str | None) -> str:
    clean_email = (email or "").lower().strip()
    if not clean_email:
        raise SystemExit("ERROR: --email is required")
    if "@" not in clean_email:
        raise SystemExit("ERROR: --email must look like an email address")
    return clean_email


def _require_frontend_base_url(frontend_base_url: str | None) -> str:
    base_url = (frontend_base_url or "").strip().rstrip("/")
    if not base_url:
        raise SystemExit("ERROR: --frontend-base-url is required")
    if not (base_url.startswith("http://") or base_url.startswith("https://")):
        raise SystemExit("ERROR: --frontend-base-url must start with http:// or https://")
    return base_url


def _validate_source(source: str | None) -> str:
    value = (source or "dev").strip()
    if value not in {"dev", "admin"}:
        raise SystemExit("ERROR: --source must be dev or admin")
    return value


def command_create_link(args: argparse.Namespace) -> int:
    email = _require_email(args.email)
    frontend_base_url = _require_frontend_base_url(args.frontend_base_url)
    source = _validate_source(args.source)
    expires_minutes = int(args.expires_minutes)

    if expires_minutes < 5 or expires_minutes > 1440:
        raise SystemExit("ERROR: --expires-minutes must be between 5 and 1440")

    with SessionLocal() as db:
        if not _table_exists(db, RESET_TOKEN_TABLE):
            _print_json(
                {
                    "status": "error",
                    "error": "missing_reset_token_table",
                    "table": RESET_TOKEN_TABLE,
                }
            )
            return 2

        created = create_password_reset_for_email(
            db,
            email=email,
            source=source,
            frontend_base_url=frontend_base_url,
            requested_ip="admin_tool",
            requested_user_agent="tools/ops/password_reset_admin.py",
            expires_minutes=expires_minutes,
        )

    if created.get("status") != "created":
        _print_json(
            {
                "status": "not_found",
                "email": email,
                "token_created": False,
                "message": "No active user found for this email.",
                "safety": {
                    "token_hash_exposed": False,
                    "password_changed": False,
                },
            }
        )
        return 3

    _print_json(
        {
            "status": "created",
            "email": created.get("email"),
            "user_id": created.get("user_id"),
            "reset_url": created.get("reset_url"),
            "token_hint": created.get("token_hint"),
            "expires_at": created.get("expires_at"),
            "source": source,
            "expires_minutes": expires_minutes,
            "safety": {
                "token_hash_exposed": False,
                "password_changed": False,
                "raw_token_stored": False,
            },
        }
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate admin/dev password reset links for GreenBrain users."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    create = sub.add_parser(
        "create-link",
        help="Create a password reset link for an existing user email.",
    )
    create.add_argument("--email", required=True, help="User email to reset.")
    create.add_argument(
        "--frontend-base-url",
        required=True,
        help="Frontend base URL, e.g. http://localhost:8090 or https://app.greenbrain.it.",
    )
    create.add_argument(
        "--source",
        default="dev",
        choices=["dev", "admin"],
        help="Reset token source. Default: dev.",
    )
    create.add_argument(
        "--expires-minutes",
        type=int,
        default=60,
        help="Reset link duration in minutes, between 5 and 1440. Default: 60.",
    )
    create.set_defaults(func=command_create_link)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
