#!/usr/bin/env bash
set -euo pipefail

cd /opt/greenbrain-platform

MIGRATION="supabase/sql/2026-05-07_customer_runtime_tokens_and_heartbeat.sql"
CHECK="tools/customer_runtime/check_runtime_cloud_schema.sql"

test -f "$MIGRATION" || { echo "MISSING $MIGRATION"; exit 1; }
test -f "$CHECK" || { echo "MISSING $CHECK"; exit 1; }

: "${SUPABASE_DB_URL:?Set SUPABASE_DB_URL first}"

echo "===== APPLY RUNTIME CLOUD MIGRATION ====="
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f "$MIGRATION"

echo
echo "===== CHECK RUNTIME CLOUD SCHEMA ====="
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f "$CHECK"
