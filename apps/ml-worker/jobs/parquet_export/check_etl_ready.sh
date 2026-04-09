#!/bin/bash
set -Eeuo pipefail

export APP_ENV="${APP_ENV:-dev}"
source /opt/greenbrain-platform/infra/scripts/load_env.sh
export PGPASSWORD="$PG_PASSWORD"

out="$(
psql \
  "host=$PG_HOST port=$PG_PORT dbname=$PG_DB user=$PG_USER sslmode=${PG_SSLMODE:-require}" \
  -Atqc "
with raw_max as (
  select max(data_movimento)::date as raw_last
  from public.greenhouse_sales_raw
),
last_ok as (
  select
    run_id,
    started_at,
    (payload->>'target_last')::date as target_last,
    payload->>'rebuild_days' as rebuild_days
  from etl.t_etl_runs
  where pipeline = 'greenhouse_daily_full'
    and status = 'success'
  order by started_at desc
  limit 1
)
select case
  when exists (
    select 1
    from raw_max r
    join last_ok l on l.target_last = r.raw_last
    where r.raw_last is not null
      and l.started_at >= now() - interval '24 hours'
  )
  then 'READY'
  else 'NOT_READY'
end;
")"

test "$out" = "READY"
