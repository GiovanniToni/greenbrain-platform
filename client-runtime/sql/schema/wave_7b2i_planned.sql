-- GreenBrain Client Runtime — Wave 7B.2-I Ops Pipeline Status
--
-- STATUS: PLANNED
--
-- Scope: exactly 1 endpoint:
--   /api/v1/ops/pipeline-status
--
-- Backend reads:
--   ml_ops.v_pipeline_runs_recent_v1
--
-- Strategy:
--   SAFE LOCAL STUB (schema + view)
--
-- Objects:
--   1 schema
--   1 view
--
-- No tables
-- No functions
--

CREATE SCHEMA IF NOT EXISTS ml_ops;

CREATE OR REPLACE VIEW ml_ops.v_pipeline_runs_recent_v1 AS
SELECT
    0::bigint        AS run_id,
    'demo'::text     AS job_type,
    'manual'::text   AS trigger_mode,
    'idle'::text     AS status,
    now()::timestamp AS started_at,
    NULL::timestamp  AS finished_at,
    0::numeric       AS duration_min,
    'local'::text    AS host_name,
    0::bigint        AS rows_processed,
    NULL::text       AS error_message,
    NULL::text       AS git_sha,
    NULL::text       AS notes;
