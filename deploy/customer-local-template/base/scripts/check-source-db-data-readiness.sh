#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV="$ROOT/overlay/env/customer-local.env"

[ -f "$ENV" ] || { echo "SOURCE_DB_DATA_READINESS_FAILED missing_env:$ENV"; exit 0; }

set -a
# shellcheck disable=SC1090
source "$ENV"
set +a

SQL=$(cat <<'SQL'
with counts as (
  select
    coalesce((select count(*) from source_import.sales_raw), 0)::bigint as source_rows,
    coalesce((select count(*) from public.greenhouse_sales_raw), 0)::bigint as public_raw_rows,
    coalesce((select count(*) from public.greenhouse_products_normalized), 0)::bigint as product_rows,
    coalesce((
      select count(*)
      from public.greenhouse_sales_raw r
      join public.greenhouse_products_normalized p on p.codart = r.codart
    ), 0)::bigint as joined_rows,
    coalesce((
      select count(*)
      from public.greenhouse_sales_raw r
      join public.greenhouse_products_normalized p on p.codart = r.codart
      where coalesce(r.movim_cassa, 0) = 1
        and coalesce(r.disattivato, 0) = 0
        and coalesce(p.is_active, true) = true
        and coalesce(p.is_classified, false) = true
        and p.famiglia is not null
        and p.categoria_corretta is not null
        and p.fascia_corretta is not null
        and p.fascia_prezzo_iva_inc is not null
    ), 0)::bigint as eligible_rows
)
select
  source_rows,
  public_raw_rows,
  product_rows,
  joined_rows,
  eligible_rows,
  case
    when source_rows = 0 then 'SOURCE_DB_RAW_EMPTY'
    when public_raw_rows = 0 then 'SOURCE_DB_RAW_PROMOTION_REQUIRED'
    when product_rows = 0 then 'PRODUCT_NORMALIZATION_REQUIRED'
    when joined_rows = 0 then 'PRODUCT_NORMALIZATION_NO_MATCHES'
    when eligible_rows = 0 then 'PRODUCT_NORMALIZATION_INCOMPLETE'
    else 'DASHBOARD_PIPELINE_READY'
  end as readiness_status
from counts;
SQL
)

run_host_docker() {
  docker compose -f "$ROOT/docker-compose.local.yml" --env-file "$ENV" exec -T postgres \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -c "$SQL"
}

run_container_psql() {
  local db_url="${DATABASE_URL:-}"
  if [ -z "$db_url" ]; then
    db_url="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}"
  fi
  psql "$db_url" -v ON_ERROR_STOP=1 -c "$SQL"
}

if [ -f /.dockerenv ] && command -v psql >/dev/null 2>&1; then
  run_container_psql
elif command -v docker >/dev/null 2>&1; then
  run_host_docker
elif command -v psql >/dev/null 2>&1; then
  run_container_psql
else
  echo "SOURCE_DB_DATA_READINESS_FAILED no_psql_or_docker"
  exit 0
fi

echo "SOURCE_DB_DATA_READINESS_CHECK_DONE"
