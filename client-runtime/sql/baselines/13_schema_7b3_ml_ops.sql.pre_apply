-- Runtime Wave 7B.3 — ml_ops schema

CREATE SCHEMA IF NOT EXISTS ml_ops;

CREATE TABLE IF NOT EXISTS ml_ops.pipeline_run_log_v1 (
    run_id TEXT PRIMARY KEY,
    job_type TEXT,
    trigger_mode TEXT,
    status TEXT,
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    duration_min NUMERIC(8,2),
    host_name TEXT,
    rows_processed INTEGER,
    error_message TEXT,
    git_sha TEXT,
    notes TEXT
);

CREATE TABLE IF NOT EXISTS ml_ops.family_run_log_v1 (
    family_run_id TEXT PRIMARY KEY,
    pipeline_run_id TEXT,
    job_type TEXT,
    family_name TEXT,
    demand_class_final TEXT,
    model_code TEXT,
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    status TEXT,
    rows_written INTEGER,
    artifact_path TEXT,
    error_message TEXT,
    error_trace TEXT
);

CREATE TABLE IF NOT EXISTS public.t_ops_pipeline_monitor (
    id SERIAL PRIMARY KEY,
    snap_ts TIMESTAMPTZ NOT NULL DEFAULT now(),
    ok BOOLEAN NOT NULL DEFAULT false
);

DROP VIEW IF EXISTS ml_ops.v_pipeline_runs_recent_v1;
DROP VIEW IF EXISTS ml_ops.v_daily_pipeline_summary_v1;
DROP VIEW IF EXISTS public.v_ops_pipeline_status;

CREATE VIEW ml_ops.v_pipeline_runs_recent_v1 AS
SELECT
    run_id,
    job_type,
    trigger_mode,
    status,
    started_at,
    finished_at,
    duration_min,
    host_name,
    rows_processed,
    error_message,
    git_sha,
    notes
FROM ml_ops.pipeline_run_log_v1
ORDER BY started_at DESC;

CREATE VIEW ml_ops.v_daily_pipeline_summary_v1 AS
SELECT
    started_at::date AS day,
    job_type,
    count(*) AS runs,
    count(*) FILTER (WHERE status = 'ok') AS ok_runs,
    count(*) FILTER (WHERE status <> 'ok') AS bad_runs
FROM ml_ops.pipeline_run_log_v1
GROUP BY 1, 2;

CREATE VIEW public.v_ops_pipeline_status AS
SELECT
    id,
    snap_ts,
    ok
FROM public.t_ops_pipeline_monitor;
