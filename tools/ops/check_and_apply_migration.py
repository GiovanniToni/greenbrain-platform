#!/usr/bin/env python3
"""
Verifica se la migration 2026-04-22_customer_cancellation_fields.sql
è già stata applicata al database Supabase.

Usage:
    python3 tools/ops/check_and_apply_migration.py

Legge SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY da infra/env/dev.env.
Non modifica mai il database — fornisce solo lo stato e le istruzioni
per applicare la migration se mancante.
"""
from __future__ import annotations

import os
import sys
import urllib.error
import urllib.request

ROOT = "/opt/greenbrain-platform"
ENV_FILE = os.path.join(ROOT, "infra", "env", "dev.env")
MIGRATION_FILE = os.path.join(ROOT, "supabase", "sql", "2026-04-22_customer_cancellation_fields.sql")

COLUMNS_TO_CHECK = ["cancellation_requested", "cancellation_requested_at"]


def read_env(path: str) -> dict:
    env: dict = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            env[key.strip()] = val.strip().strip('"').strip("'")
    return env


def check_columns(supabase_url: str, service_key: str) -> tuple[bool, str]:
    """
    Attempt to SELECT the cancellation columns from gb_customer_companies.
    Returns (columns_exist: bool, detail_message: str).
    A successful response (even with 0 rows) means the columns are present.
    A 400/PGRST error mentioning 'does not exist' means migration not applied.
    """
    cols = ",".join(COLUMNS_TO_CHECK)
    url = f"{supabase_url}/rest/v1/gb_customer_companies?select={cols}&limit=1"
    req = urllib.request.Request(url)
    req.add_header("apikey", service_key)
    req.add_header("Authorization", f"Bearer {service_key}")
    req.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            return True, f"Colonne presenti — HTTP {resp.status}"
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        if "does not exist" in body or "42703" in body:
            return False, f"Colonne MANCANTI — HTTP {e.code}: {body}"
        return False, f"Errore HTTP {e.code}: {body}"
    except Exception as exc:
        return False, f"Errore di connessione: {exc}"


def print_migration_instructions(migration_sql: str, supabase_url: str) -> None:
    project_ref = ""
    try:
        host = supabase_url.rstrip("/").split("//")[-1].split(".")[0]
        project_ref = host
    except Exception:
        project_ref = "<project-ref>"

    print()
    print("=" * 64)
    print("MIGRATION NON APPLICATA")
    print("=" * 64)
    print()
    print("Opzione 1 — Supabase Studio (consigliata):")
    print(f"  1. Apri https://supabase.com/dashboard/project/{project_ref}/sql")
    print("  2. Incolla il seguente SQL e clicca RUN:")
    print()
    print("  " + "-" * 60)
    for line in migration_sql.strip().splitlines():
        print(f"  {line}")
    print("  " + "-" * 60)
    print()
    print("Opzione 2 — psql (richiede connection string dal Dashboard):")
    print("  Vai su: Supabase Dashboard → Settings → Database → Connection string")
    print("  Poi esegui:")
    print(f"    psql \"$DB_URL\" -f {MIGRATION_FILE}")
    print()
    print("Dopo aver applicato la migration, rilancia questo script per conferma.")
    print()


def main() -> int:
    if not os.path.exists(ENV_FILE):
        print(f"ERRORE: env file non trovato: {ENV_FILE}", file=sys.stderr)
        return 1

    env = read_env(ENV_FILE)
    supabase_url = env.get("SUPABASE_URL", "").rstrip("/")
    service_key = env.get("SUPABASE_SERVICE_ROLE_KEY", "")

    if not supabase_url or not service_key:
        print(
            "ERRORE: SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY mancanti in dev.env",
            file=sys.stderr,
        )
        return 1

    print(f"Supabase URL : {supabase_url}")
    print(f"Colonne da verificare: {', '.join(COLUMNS_TO_CHECK)}")
    print()

    ok, detail = check_columns(supabase_url, service_key)
    print(f"Risultato: {detail}")

    if ok:
        print()
        print("✓ Migration già applicata. Nessuna azione necessaria.")
        print()
        print("Il campo cancellation_requested e cancellation_requested_at")
        print("sono presenti in gb_customer_companies e pronti per l'uso.")
        return 0

    migration_sql = ""
    if os.path.exists(MIGRATION_FILE):
        with open(MIGRATION_FILE) as f:
            migration_sql = f.read()
    else:
        migration_sql = (
            "ALTER TABLE gb_customer_companies\n"
            "  ADD COLUMN IF NOT EXISTS cancellation_requested      BOOLEAN     NOT NULL DEFAULT FALSE,\n"
            "  ADD COLUMN IF NOT EXISTS cancellation_requested_at   TIMESTAMPTZ;\n"
        )

    print_migration_instructions(migration_sql, supabase_url)
    return 2


if __name__ == "__main__":
    sys.exit(main())
