-- =============================================================
-- BLOCCO D — Consolidamento monitoring su ml_ops
-- Strategia: ml_ops diventa layer unico autorevole.
--            ml_monitor viene lasciato intatto (read-only/deprecato).
--            NON si droppa nulla.
-- =============================================================

BEGIN;

-- -------------------------------------------------------------
-- STEP 1: aggiunte a ml_ops.pipeline_run_log_v1
-- Parità con i campi di ml_monitor.runs utili operativamente
-- -------------------------------------------------------------
ALTER TABLE ml_ops.pipeline_run_log_v1
    ADD COLUMN IF NOT EXISTS git_sha       TEXT,
    ADD COLUMN IF NOT EXISTS env_snapshot  JSONB;


-- -------------------------------------------------------------
-- STEP 2: aggiunte a ml_ops.family_run_log_v1
-- error_trace permette il debug senza aprire ml_monitor.family_runs
-- -------------------------------------------------------------
ALTER TABLE ml_ops.family_run_log_v1
    ADD COLUMN IF NOT EXISTS error_trace TEXT;


-- -------------------------------------------------------------
-- STEP 3: nuove viste monitoring consolidate in ml_ops
-- Sostituiscono ml_monitor.v_run_recent, v_daily_runs,
-- v_daily_family_summary, v_model_status, v_model_stale.
-- -------------------------------------------------------------

-- 3a. Recent pipeline runs (→ sostituisce ml_monitor.v_run_recent)
DROP VIEW IF EXISTS ml_ops.v_pipeline_runs_recent_v1;
CREATE VIEW ml_ops.v_pipeline_runs_recent_v1 AS
SELECT
    run_id,
    job_type,
    trigger_mode,
    status,
    started_at,
    finished_at,
    ROUND(
        EXTRACT(EPOCH FROM COALESCE(finished_at, now()) - started_at) / 60.0,
        1
    )                           AS duration_min,
    host_name,
    rows_processed,
    error_message,
    git_sha,
    notes
FROM ml_ops.pipeline_run_log_v1
ORDER BY started_at DESC, run_id DESC;

COMMENT ON VIEW ml_ops.v_pipeline_runs_recent_v1 IS
    'Blocco D: sostituisce ml_monitor.v_run_recent. '
    'Mostra i run di pipeline recenti da ml_ops.pipeline_run_log_v1.';


-- 3b. Daily pipeline summary (→ sostituisce ml_monitor.v_daily_runs)
DROP VIEW IF EXISTS ml_ops.v_daily_pipeline_summary_v1;
CREATE VIEW ml_ops.v_daily_pipeline_summary_v1 AS
SELECT
    DATE_TRUNC('day', started_at)::date         AS day,
    job_type,
    COUNT(*)                                     AS runs,
    COUNT(*) FILTER (WHERE status = 'success')  AS ok_runs,
    COUNT(*) FILTER (WHERE status = 'failed')   AS bad_runs,
    MIN(started_at)                              AS first_run_at,
    MAX(finished_at)                             AS last_finished_at
FROM ml_ops.pipeline_run_log_v1
GROUP BY 1, 2
ORDER BY 1 DESC, 2;

COMMENT ON VIEW ml_ops.v_daily_pipeline_summary_v1 IS
    'Blocco D: sostituisce ml_monitor.v_daily_runs. '
    'Aggregazione giornaliera dei run di pipeline per job_type.';


-- 3c. Per-family operational status (→ sostituisce ml_monitor.v_model_status)
-- Usa ml_forecast.family_model_state_v1 per train/predict recency (già autorevole)
-- e ml_ops.family_run_log_v1 per artifact_path ed error detail.
DROP VIEW IF EXISTS ml_ops.v_family_ops_status_v1;
CREATE VIEW ml_ops.v_family_ops_status_v1 AS
WITH last_train AS (
    SELECT DISTINCT ON (family_name)
        family_name,
        family_run_id                                        AS train_family_run_id,
        started_at                                           AS train_started_at,
        finished_at                                          AS train_finished_at,
        status                                               AS train_status,
        error_message                                        AS train_error_message,
        error_trace                                          AS train_error_trace,
        artifact_path
    FROM ml_ops.family_run_log_v1
    WHERE job_type ILIKE 'train%'
    ORDER BY family_name, started_at DESC
),
last_predict AS (
    SELECT DISTINCT ON (family_name)
        family_name,
        family_run_id                                        AS predict_family_run_id,
        started_at                                           AS predict_started_at,
        finished_at                                          AS predict_finished_at,
        status                                               AS predict_status,
        rows_written                                         AS predict_rows_written,
        error_message                                        AS predict_error_message,
        error_trace                                          AS predict_error_trace
    FROM ml_ops.family_run_log_v1
    WHERE job_type ILIKE 'predict%'
    ORDER BY family_name, started_at DESC
)
SELECT
    s.family_name,
    s.demand_class_final,
    -- Train state
    s.last_train_at,
    s.last_train_status,
    s.needs_initial_train,
    s.needs_retrain,
    -- Predict state
    s.last_predict_at,
    s.last_predict_status,
    s.needs_predict,
    -- Bundle freshness (proxy: last successful train)
    ROUND(EXTRACT(EPOCH FROM now() - s.last_train_at) / 86400.0, 1)
                                                             AS bundle_age_days,
    lt.artifact_path                                         AS bundle_path,
    -- Derived model state
    CASE
        WHEN s.last_train_at IS NULL                         THEN 'never_trained'
        WHEN s.last_train_status = 'failed'                  THEN 'train_failed'
        WHEN s.last_predict_status = 'failed'                THEN 'predict_failed'
        WHEN s.last_train_at < now() - INTERVAL '90 days'   THEN 'stale_90d'
        ELSE 'ok'
    END                                                      AS model_state,
    -- Latest train run detail
    lt.train_family_run_id,
    lt.train_started_at,
    lt.train_finished_at,
    lt.train_status,
    lt.train_error_message,
    lt.train_error_trace,
    -- Latest predict run detail
    lp.predict_family_run_id,
    lp.predict_started_at,
    lp.predict_finished_at,
    lp.predict_status,
    lp.predict_rows_written,
    lp.predict_error_message,
    lp.predict_error_trace
FROM ml_forecast.family_model_state_v1 s
LEFT JOIN last_train  lt ON lt.family_name = s.family_name
LEFT JOIN last_predict lp ON lp.family_name = s.family_name
ORDER BY s.family_name;

COMMENT ON VIEW ml_ops.v_family_ops_status_v1 IS
    'Blocco D: sostituisce ml_monitor.v_model_status. '
    'Stato operativo per famiglia: train/predict recency, bundle freshness, model_state. '
    'Usa ml_forecast.family_model_state_v1 come fonte autorevole di train/predict timestamps.';


-- 3d. Stale families (→ sostituisce ml_monitor.v_model_stale)
DROP VIEW IF EXISTS ml_ops.v_model_stale_v1;
CREATE VIEW ml_ops.v_model_stale_v1 AS
SELECT
    family_name,
    demand_class_final,
    last_train_at,
    bundle_age_days,
    model_state,
    bundle_path
FROM ml_ops.v_family_ops_status_v1
WHERE model_state IN ('stale_90d', 'never_trained', 'train_failed')
   OR needs_initial_train = TRUE
   OR needs_retrain       = TRUE
ORDER BY bundle_age_days DESC NULLS FIRST;

COMMENT ON VIEW ml_ops.v_model_stale_v1 IS
    'Blocco D: sostituisce ml_monitor.v_model_stale. '
    'Famiglie con modelli scaduti, mai trainati o con train fallito.';


-- -------------------------------------------------------------
-- STEP 4: commento deprecazione sulle viste ml_monitor
-- NON si droppano — solo marcate come deprecated per documentazione
-- -------------------------------------------------------------
COMMENT ON VIEW ml_monitor.v_run_recent IS
    '[DEPRECATED — Blocco D] Sostituita da ml_ops.v_pipeline_runs_recent_v1. '
    'Da eliminare dopo periodo di transizione.';

COMMENT ON VIEW ml_monitor.v_daily_runs IS
    '[DEPRECATED — Blocco D] Sostituita da ml_ops.v_daily_pipeline_summary_v1. '
    'Da eliminare dopo periodo di transizione.';

COMMENT ON VIEW ml_monitor.v_daily_family_summary IS
    '[DEPRECATED — Blocco D] Vedere ml_ops.v_family_ops_status_v1. '
    'Da eliminare dopo periodo di transizione.';

COMMENT ON VIEW ml_monitor.v_model_status IS
    '[DEPRECATED — Blocco D] Sostituita da ml_ops.v_family_ops_status_v1. '
    'Da eliminare dopo periodo di transizione.';

COMMENT ON VIEW ml_monitor.v_model_stale IS
    '[DEPRECATED — Blocco D] Sostituita da ml_ops.v_model_stale_v1. '
    'Da eliminare dopo periodo di transizione.';


-- -------------------------------------------------------------
-- STEP 5: verifica finale
-- -------------------------------------------------------------
DO $$
DECLARE
    v_col_git_sha      BOOLEAN;
    v_col_env          BOOLEAN;
    v_col_etrace       BOOLEAN;
    v_view_pipe_recent BOOLEAN;
    v_view_daily_pipe  BOOLEAN;
    v_view_fam_ops     BOOLEAN;
    v_view_stale       BOOLEAN;
BEGIN
    SELECT COUNT(*) > 0 INTO v_col_git_sha
    FROM information_schema.columns
    WHERE table_schema='ml_ops' AND table_name='pipeline_run_log_v1'
      AND column_name='git_sha';

    SELECT COUNT(*) > 0 INTO v_col_env
    FROM information_schema.columns
    WHERE table_schema='ml_ops' AND table_name='pipeline_run_log_v1'
      AND column_name='env_snapshot';

    SELECT COUNT(*) > 0 INTO v_col_etrace
    FROM information_schema.columns
    WHERE table_schema='ml_ops' AND table_name='family_run_log_v1'
      AND column_name='error_trace';

    SELECT COUNT(*) > 0 INTO v_view_pipe_recent
    FROM pg_views WHERE schemaname='ml_ops' AND viewname='v_pipeline_runs_recent_v1';

    SELECT COUNT(*) > 0 INTO v_view_daily_pipe
    FROM pg_views WHERE schemaname='ml_ops' AND viewname='v_daily_pipeline_summary_v1';

    SELECT COUNT(*) > 0 INTO v_view_fam_ops
    FROM pg_views WHERE schemaname='ml_ops' AND viewname='v_family_ops_status_v1';

    SELECT COUNT(*) > 0 INTO v_view_stale
    FROM pg_views WHERE schemaname='ml_ops' AND viewname='v_model_stale_v1';

    RAISE NOTICE '--- BLOCCO D verifica OK ---';
    RAISE NOTICE 'pipeline_run_log_v1.git_sha: %',      CASE WHEN v_col_git_sha  THEN 'presente' ELSE 'MANCANTE' END;
    RAISE NOTICE 'pipeline_run_log_v1.env_snapshot: %', CASE WHEN v_col_env      THEN 'presente' ELSE 'MANCANTE' END;
    RAISE NOTICE 'family_run_log_v1.error_trace: %',    CASE WHEN v_col_etrace   THEN 'presente' ELSE 'MANCANTE' END;
    RAISE NOTICE 'Vista v_pipeline_runs_recent_v1: %',  CASE WHEN v_view_pipe_recent THEN 'presente' ELSE 'MANCANTE' END;
    RAISE NOTICE 'Vista v_daily_pipeline_summary_v1: %',CASE WHEN v_view_daily_pipe  THEN 'presente' ELSE 'MANCANTE' END;
    RAISE NOTICE 'Vista v_family_ops_status_v1: %',     CASE WHEN v_view_fam_ops     THEN 'presente' ELSE 'MANCANTE' END;
    RAISE NOTICE 'Vista v_model_stale_v1: %',           CASE WHEN v_view_stale       THEN 'presente' ELSE 'MANCANTE' END;
    RAISE NOTICE '--- Fine BLOCCO D ---';

    IF NOT (v_col_git_sha AND v_col_env AND v_col_etrace
        AND v_view_pipe_recent AND v_view_daily_pipe
        AND v_view_fam_ops AND v_view_stale)
    THEN
        RAISE EXCEPTION 'BLOCCO D verifica fallita — rollback';
    END IF;
END;
$$;

COMMIT;
