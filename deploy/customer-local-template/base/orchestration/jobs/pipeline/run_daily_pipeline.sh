#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/orchestration/lib/common.sh"

gb_load_env

gb_log "PIPELINE_START raw->fact->dense->features->monitor"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -P pager=off -c "
set statement_timeout=0;
call public.run_greenhouse_daily_pipeline_full(3,14,1);
"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -P pager=off -c "
select public.ops_refresh_pipeline_monitor_snapshot();
"

gb_log "PIPELINE_DONE"
