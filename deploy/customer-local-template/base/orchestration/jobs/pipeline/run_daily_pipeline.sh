#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/orchestration/lib/common.sh"

gb_load_env

REBUILD_DAYS="${REBUILD_DAYS:-14}"

gb_log "PIPELINE_START local raw->fact->dense->features"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -P pager=off -c "
set statement_timeout=0;

with bounds as (
  select
    greatest(
      coalesce(max(data_movimento)::date, current_date) - (${REBUILD_DAYS}::int - 1),
      date '2000-01-01'
    ) as start_day,
    coalesce(max(data_movimento)::date, current_date) as end_day
  from public.greenhouse_sales_raw
)
select
  public.refresh_fact_from_raw(start_day, end_day) as fact_result,
  public.refresh_dense_range_from_fact(start_day, end_day) as dense_result,
  public.refresh_forecast_features_dense_range(start_day, end_day) as features_result
from bounds;
"

gb_log "PIPELINE_DONE local"
