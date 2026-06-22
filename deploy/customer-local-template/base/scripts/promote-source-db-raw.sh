#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV="$ROOT/overlay/env/customer-local.env"
SOURCE_ENV="$ROOT/overlay/env/source-db.env"
SQL_FILE="$ROOT/base/client-runtime/sql/init/28_source_db_promote_to_greenhouse_raw.sql"
LOG_DIR="$ROOT/overlay/logs/source-db"

mkdir -p "$LOG_DIR"

PERM_SCRIPT="$ROOT/base/scripts/fix-source-db-log-permissions.sh"
if [ -x "$PERM_SCRIPT" ]; then
  bash "$PERM_SCRIPT" >/dev/null 2>&1 || true
fi

TS="$(date -u +%Y%m%d_%H%M%S)"
LOG="$LOG_DIR/source_db_raw_promotion_${TS}.log"
LATEST="$LOG_DIR/source_db_raw_promotion_latest.log"

echo "== GreenBrain Source DB Raw Promotion ==" | tee "$LOG"

if [ ! -f "$SOURCE_ENV" ]; then
  echo "SOURCE_DB_RAW_PROMOTION_SKIPPED_NOT_CONFIGURED" | tee -a "$LOG"
  ln -sfn "$(basename "$LOG")" "$LATEST"
  exit 0
fi

if [ ! -f "$SQL_FILE" ]; then
  echo "SOURCE_DB_RAW_PROMOTION_FAILED missing_sql_file:$SQL_FILE" | tee -a "$LOG"
  ln -sfn "$(basename "$LOG")" "$LATEST"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV"
# shellcheck disable=SC1090
source "$SOURCE_ENV"
set +a

CLIENT_CODE="${SOURCE_DB_CLIENT_CODE:-${SOURCE_CLIENT_CODE:-${TENANT_CODE:-${CUSTOMER_TENANT_CODE:-}}}}"

run_host_docker() {
  docker compose -f "$ROOT/docker-compose.local.yml" --env-file "$ENV" exec -T postgres \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -f /dev/stdin < "$SQL_FILE"

  docker compose -f "$ROOT/docker-compose.local.yml" --env-file "$ENV" exec -T postgres \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -v source_client_code="$CLIENT_CODE" <<'SQL'
\timing on
select * from public.promote_source_import_sales_raw_to_greenhouse_raw(NULLIF(:'source_client_code', ''));

select 'source_import.sales_raw' as table_name, count(*) as rows
from source_import.sales_raw
where NULLIF(:'source_client_code', '') is null
   or source_client_code = NULLIF(:'source_client_code', '');

select 'public.greenhouse_sales_raw' as table_name, count(*) as rows
from public.greenhouse_sales_raw;

select min(data_movimento) as min_data, max(data_movimento) as max_data
from public.greenhouse_sales_raw;
SQL
}

run_container_psql() {
  local db_url="${DATABASE_URL:-}"
  if [ -z "$db_url" ]; then
    db_url="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}"
  fi

  psql "$db_url" -v ON_ERROR_STOP=1 -f "$SQL_FILE"

  psql "$db_url" -v ON_ERROR_STOP=1 -v source_client_code="$CLIENT_CODE" <<'SQL'
\timing on
select * from public.promote_source_import_sales_raw_to_greenhouse_raw(NULLIF(:'source_client_code', ''));

select 'source_import.sales_raw' as table_name, count(*) as rows
from source_import.sales_raw
where NULLIF(:'source_client_code', '') is null
   or source_client_code = NULLIF(:'source_client_code', '');

select 'public.greenhouse_sales_raw' as table_name, count(*) as rows
from public.greenhouse_sales_raw;

select min(data_movimento) as min_data, max(data_movimento) as max_data
from public.greenhouse_sales_raw;
SQL
}

set +e
if [ -f /.dockerenv ] && command -v psql >/dev/null 2>&1; then
  run_container_psql 2>&1 | tee -a "$LOG"
  RC="${PIPESTATUS[0]}"
elif command -v docker >/dev/null 2>&1; then
  run_host_docker 2>&1 | tee -a "$LOG"
  RC="${PIPESTATUS[0]}"
elif command -v psql >/dev/null 2>&1; then
  run_container_psql 2>&1 | tee -a "$LOG"
  RC="${PIPESTATUS[0]}"
else
  echo "SOURCE_DB_RAW_PROMOTION_FAILED no_psql_or_docker" | tee -a "$LOG"
  RC=1
fi
set -e

ln -sfn "$(basename "$LOG")" "$LATEST"

if [ "$RC" -ne 0 ]; then
  echo "SOURCE_DB_RAW_PROMOTION_FAILED rc=$RC" | tee -a "$LOG"
  exit "$RC"
fi

echo "SOURCE_DB_RAW_PROMOTION_OK" | tee -a "$LOG"
