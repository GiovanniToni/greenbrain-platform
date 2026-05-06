#!/usr/bin/env bash
set -euo pipefail

GB_BASE="${GB_BASE:-/opt/greenbrain-platform}"
cd "$GB_BASE"

source "$GB_BASE/infra/scripts/load_env.sh"

psql -v ON_ERROR_STOP=1 -P pager=off "$DATABASE_URL" -c "
set statement_timeout=0;
call public.run_greenhouse_daily_pipeline_full(3,14,1);
"

psql -v ON_ERROR_STOP=1 -P pager=off "$DATABASE_URL" -c "
select public.ops_refresh_pipeline_monitor_snapshot();
"
