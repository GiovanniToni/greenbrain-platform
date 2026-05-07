-- Daily sequential runtime monitor views

create or replace view public.v_ops_daily_sequence_steps_latest as
with last_etl as (
  select *
  from etl.t_etl_runs
  where pipeline = 'greenhouse_daily_full'
  order by started_at desc
  limit 1
),
seq_window as (
  select
    started_at as sequence_started_at,
    coalesce(ended_at, started_at) as etl_finished_at,
    (payload->>'target_last')::date as target_date
  from last_etl
),
parquet as (
  select
    min(started_at) as started_at,
    max(ended_at) as ended_at,
    case when count(*) = 17 and count(*) filter (where status='success') = 17
      then 'success' else 'failed' end as status,
    count(*) as batches,
    sum(n_families) as families,
    sum(n_files) as files,
    sum(n_rows) as rows,
    string_agg(nullif(error_message,''), ' | ') filter (where nullif(error_message,'') is not null) as message
  from public.ops_parquet_export_runs p
  join seq_window w on p.started_at >= w.etl_finished_at
  where p.dataset = 'features_dense_ml_clean'
    and p.meta->>'full_export' = 'false'
    and p.to_day = w.target_date
),
registry as (
  select *
  from ml_ops.pipeline_run_log_v1 r
  join seq_window w on r.started_at >= coalesce((select ended_at from parquet), w.etl_finished_at)
  where r.job_type = 'refresh_registry'
  order by r.started_at
  limit 1
),
train_missing as (
  select *
  from ml_ops.pipeline_run_log_v1 r
  join seq_window w on r.started_at >= coalesce((select finished_at from registry), w.etl_finished_at)
  where r.job_type = 'train_missing'
  order by r.started_at
  limit 1
),
predict as (
  select *
  from ml_ops.pipeline_run_log_v1 r
  join seq_window w on r.started_at >= coalesce((select finished_at from train_missing), w.etl_finished_at)
  where r.job_type = 'predict_daily'
  order by r.started_at
  limit 1
)
select 1 as step_order, 'raw_wait_and_daily_pipeline' as step_name,
       e.started_at, e.ended_at, e.status,
       null::bigint as rows_processed,
       e.message
from last_etl e
union all
select 2, 'parquet_export',
       p.started_at, p.ended_at, p.status,
       p.rows,
       concat('batches=',p.batches,' families=',p.families,' files=',p.files, coalesce(' | '||p.message,''))
from parquet p
union all
select 3, 'refresh_registry',
       r.started_at, r.finished_at, r.status,
       r.rows_processed::bigint,
       coalesce(r.error_message, r.notes)
from registry r
union all
select 4, 'train_missing',
       t.started_at, t.finished_at, t.status,
       t.rows_processed::bigint,
       coalesce(t.error_message, t.notes)
from train_missing t
union all
select 5, 'predict_all',
       p.started_at, p.finished_at, p.status,
       p.rows_processed::bigint,
       coalesce(p.error_message, p.notes)
from predict p;

create or replace view public.v_ops_daily_sequence_health_latest as
with s as (
  select *
  from public.v_ops_daily_sequence_steps_latest
),
agg as (
  select
    min(started_at) as sequence_started_at,
    max(ended_at) as sequence_finished_at,
    count(*) as steps_found,
    count(*) filter (where status = 'success') as steps_success,
    count(*) filter (where status <> 'success' or status is null) as steps_bad,
    string_agg(step_name || '=' || coalesce(status,'missing'), ' | ' order by step_order) as step_statuses
  from s
)
select
  sequence_started_at,
  sequence_finished_at,
  round(extract(epoch from (sequence_finished_at - sequence_started_at))/60.0, 2) as duration_min,
  steps_found,
  steps_success,
  steps_bad,
  (
    steps_found = 5
    and steps_success = 5
  ) as ok,
  step_statuses
from agg;
