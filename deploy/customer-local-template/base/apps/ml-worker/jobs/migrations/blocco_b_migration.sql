-- BLOCCO B: Hardening operativo e monitoring — 2026-03-13
-- Idempotente: sicuro da rieseguire

BEGIN;

-- STEP 0: Backup routing_v2 definition
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema='ml_forecast' AND table_name='_bak_routing_v2_def_20260313') THEN
        CREATE TABLE ml_forecast._bak_routing_v2_def_20260313 (saved_at TIMESTAMPTZ DEFAULT now(), view_name TEXT, view_def TEXT);
        INSERT INTO ml_forecast._bak_routing_v2_def_20260313 (view_name, view_def)
        SELECT 'v_family_execution_routing_v2', view_definition
        FROM information_schema.views WHERE table_schema='ml_forecast' AND table_name='v_family_execution_routing_v2';
        RAISE NOTICE 'Backup routing_v2 salvato';
    END IF;
END $$;

-- STEP 1: Popola family_model_assignment_v1 con tutte le 844 famiglie attive
-- Fonte: model_code corrente da state (classificazione). NON tocca needs_retrain/needs_predict.
INSERT INTO ml_forecast.family_model_assignment_v1
    (family_name, model_code, is_locked, assigned_by, assigned_at, assignment_reason)
SELECT
    r.family_name,
    COALESCE(s.model_code, 'V4_TWEEDIE_BUNDLE'),
    FALSE, 'migration', now(), 'initial migration from current routing'
FROM ml_forecast.family_model_registry_v2 r
LEFT JOIN ml_forecast.family_model_state_v1 s ON s.family_name = r.family_name
WHERE COALESCE(s.is_active, TRUE) = TRUE
ON CONFLICT (family_name) DO NOTHING;

-- Log immutabile migration (solo per righe appena inserite, evita doppioni)
INSERT INTO ml_forecast.family_model_assignment_log_v1
    (family_name, old_model_code, new_model_code, old_is_locked, new_is_locked, changed_by, reason)
SELECT a.family_name, NULL, a.model_code, NULL, FALSE, 'migration', 'initial migration from current routing'
FROM ml_forecast.family_model_assignment_v1 a
WHERE a.assigned_by = 'migration' AND a.assignment_reason = 'initial migration from current routing'
  AND NOT EXISTS (
      SELECT 1 FROM ml_forecast.family_model_assignment_log_v1 l
      WHERE l.family_name=a.family_name AND l.changed_by='migration');

-- STEP 2: Aggiorna v_family_execution_routing_v2 — aggiunge effective_model_code esplicita
-- DROP necessario perché PG non permette rinominare colonne con CREATE OR REPLACE VIEW
DROP VIEW IF EXISTS ml_forecast.v_family_execution_routing_v2;
CREATE VIEW ml_forecast.v_family_execution_routing_v2 AS
WITH base AS (
    SELECT
        r.family_name, r.business_tier, r.demand_class_final,
        a.model_code                                                    AS assignment_model_code,
        r.model_code                                                    AS registry_model_code,
        COALESCE(a.model_code, r.model_code, 'V4_TWEEDIE_BUNDLE')      AS effective_model_code,
        CASE WHEN a.model_code IS NOT NULL THEN 'manual_assignment'
             WHEN r.model_code IS NOT NULL THEN 'class_map'
             ELSE 'fallback_v4' END                                     AS routing_source,
        COALESCE(a.is_locked, FALSE)                                    AS is_locked,
        a.assigned_by,
        r.execution_engine AS registry_execution_engine,
        r.bundle_version   AS registry_bundle_version,
        s.is_active, s.needs_initial_train, s.needs_retrain, s.needs_predict,
        s.last_train_at, s.last_predict_at, s.last_train_status, s.last_predict_status
    FROM      ml_forecast.family_model_registry_v2   r
    LEFT JOIN ml_forecast.family_model_state_v1       s  ON s.family_name = r.family_name
    LEFT JOIN ml_forecast.family_model_assignment_v1  a  ON a.family_name = r.family_name
)
SELECT
    b.family_name, b.business_tier, b.demand_class_final,
    b.effective_model_code,
    b.effective_model_code                                              AS model_code,
    b.assignment_model_code, b.registry_model_code,
    b.routing_source, b.is_locked, b.assigned_by,
    m.current_execution_engine, m.target_execution_engine,
    CASE WHEN ec.is_active=TRUE THEN m.current_execution_engine ELSE 'V4_TWEEDIE_BUNDLE' END AS effective_execution_engine,
    b.registry_execution_engine, b.registry_bundle_version,
    b.is_active, b.needs_initial_train, b.needs_retrain, b.needs_predict,
    b.last_train_at, b.last_predict_at, b.last_train_status, b.last_predict_status
FROM base b
LEFT JOIN ml_forecast.model_engine_map_v1         m  ON m.model_code       = b.effective_model_code
LEFT JOIN ml_forecast.execution_engine_catalog_v1 ec ON ec.execution_engine = m.current_execution_engine;

-- STEP 3: v_family_health_v1 — una riga per famiglia, stato completo
CREATE OR REPLACE VIEW ml_ops.v_family_health_v1 AS
SELECT
    s.family_name, s.business_tier, s.demand_class_final,
    a.model_code                                                        AS assigned_model_code,
    COALESCE(m.current_execution_engine, 'V4_TWEEDIE_BUNDLE')          AS effective_engine,
    a.is_locked, a.assigned_by, a.assigned_at,
    CASE WHEN a.model_code IS NOT NULL THEN 'manual_assignment'
         WHEN s.model_code IS NOT NULL THEN 'class_map' ELSE 'fallback_v4' END AS routing_source,
    s.last_train_at, s.last_train_status, s.needs_initial_train, s.needs_retrain,
    s.last_predict_at, s.last_predict_status, s.needs_predict,
    fmax.max_forecast_date,
    CURRENT_DATE                                                        AS today,
    (fmax.max_forecast_date - CURRENT_DATE)                            AS forecast_days_ahead,
    CASE WHEN fmax.max_forecast_date IS NULL             THEN 'no_forecast'
         WHEN fmax.max_forecast_date < CURRENT_DATE      THEN 'expired'
         WHEN fmax.max_forecast_date < CURRENT_DATE + 7  THEN 'near_expiry'
         ELSE 'fresh' END                                              AS forecast_status
FROM ml_forecast.family_model_state_v1 s
LEFT JOIN ml_forecast.family_model_assignment_v1 a ON a.family_name = s.family_name
LEFT JOIN ml_forecast.model_engine_map_v1        m ON m.model_code  = COALESCE(a.model_code, s.model_code, 'V4_TWEEDIE_BUNDLE')
LEFT JOIN (SELECT famiglia AS family_name, MAX(data) AS max_forecast_date
           FROM public.greenhouse_forecast_results_v2 GROUP BY famiglia) fmax
    ON fmax.family_name = s.family_name
WHERE s.is_active = TRUE;

-- STEP 4: v_forecast_freshness_v1 — famiglie ordinate per forecast più stale
CREATE OR REPLACE VIEW ml_ops.v_forecast_freshness_v1 AS
SELECT
    s.family_name, s.business_tier, s.demand_class_final,
    fmax.max_forecast_date,
    CURRENT_DATE                                AS today,
    (fmax.max_forecast_date - CURRENT_DATE)     AS days_ahead,
    CASE WHEN fmax.max_forecast_date IS NULL             THEN 'no_forecast'
         WHEN fmax.max_forecast_date < CURRENT_DATE      THEN 'expired'
         WHEN fmax.max_forecast_date < CURRENT_DATE + 7  THEN 'near_expiry'
         ELSE 'fresh' END                       AS freshness_status,
    s.last_predict_at, s.last_predict_status
FROM ml_forecast.family_model_state_v1 s
LEFT JOIN (SELECT famiglia AS family_name, MAX(data) AS max_forecast_date
           FROM public.greenhouse_forecast_results_v2 GROUP BY famiglia) fmax
    ON fmax.family_name = s.family_name
WHERE s.is_active = TRUE
ORDER BY fmax.max_forecast_date ASC NULLS FIRST, s.family_name;

-- STEP 5-6: Viste fallimenti recenti (7 giorni)
CREATE OR REPLACE VIEW ml_ops.v_train_failures_last7d_v1 AS
SELECT r.family_name, r.job_type, r.model_code, r.started_at, r.finished_at,
       ROUND(EXTRACT(EPOCH FROM (r.finished_at - r.started_at))::NUMERIC, 1) AS duration_sec,
       r.status, r.error_message
FROM ml_ops.family_run_log_v1 r
WHERE r.job_type ILIKE 'train%' AND r.status='failed' AND r.started_at >= now() - INTERVAL '7 days'
ORDER BY r.started_at DESC;

CREATE OR REPLACE VIEW ml_ops.v_predict_failures_last7d_v1 AS
SELECT r.family_name, r.job_type, r.model_code, r.started_at, r.finished_at,
       ROUND(EXTRACT(EPOCH FROM (r.finished_at - r.started_at))::NUMERIC, 1) AS duration_sec,
       r.status, r.error_message
FROM ml_ops.family_run_log_v1 r
WHERE r.job_type ILIKE 'predict%' AND r.status='failed' AND r.started_at >= now() - INTERVAL '7 days'
ORDER BY r.started_at DESC;

-- STEP 7: v_assignment_status_v1 — governance: aligned vs overridden
CREATE OR REPLACE VIEW ml_ops.v_assignment_status_v1 AS
SELECT
    a.family_name, s.demand_class_final,
    a.model_code                AS assigned_model_code,
    cm.model_code               AS class_default_model,
    CASE WHEN cm.model_code IS NULL         THEN 'no_class_default'
         WHEN a.model_code = cm.model_code  THEN 'aligned'
         ELSE 'overridden' END  AS alignment_status,
    a.is_locked, a.assigned_by, a.assigned_at, a.assignment_reason
FROM ml_forecast.family_model_assignment_v1 a
LEFT JOIN ml_forecast.family_model_state_v1 s  ON s.family_name        = a.family_name
LEFT JOIN ml_forecast.class_model_map_v1    cm ON cm.demand_class_final = s.demand_class_final
ORDER BY CASE WHEN a.is_locked THEN 0 ELSE 1 END,
         CASE WHEN cm.model_code IS NULL        THEN 2
              WHEN a.model_code = cm.model_code THEN 1
              ELSE                                   0 END,
         a.family_name;

-- STEP 8: v_forecast_admin_v1 — vista riassuntiva per backend/frontend
CREATE OR REPLACE VIEW ml_ops.v_forecast_admin_v1 AS
SELECT
    s.family_name, s.business_tier, s.demand_class_final,
    a.model_code                                                       AS assigned_model_code,
    COALESCE(m.current_execution_engine, 'V4_TWEEDIE_BUNDLE')         AS effective_engine,
    a.is_locked, a.assigned_by,
    CASE WHEN a.model_code IS NOT NULL THEN 'manual_assignment'
         WHEN s.model_code IS NOT NULL THEN 'class_map' ELSE 'fallback_v4' END AS routing_source,
    CASE WHEN cm.model_code IS NULL        THEN 'no_class_default'
         WHEN a.model_code = cm.model_code THEN 'aligned' ELSE 'overridden' END AS alignment_status,
    s.last_train_at, s.last_train_status, s.needs_initial_train, s.needs_retrain,
    s.last_predict_at, s.last_predict_status, s.needs_predict,
    fmax.max_forecast_date,
    (fmax.max_forecast_date - CURRENT_DATE)                           AS forecast_days_ahead,
    CASE WHEN fmax.max_forecast_date IS NULL             THEN 'no_forecast'
         WHEN fmax.max_forecast_date < CURRENT_DATE      THEN 'expired'
         WHEN fmax.max_forecast_date < CURRENT_DATE + 7  THEN 'near_expiry'
         ELSE 'fresh' END                                             AS forecast_status
FROM ml_forecast.family_model_state_v1       s
LEFT JOIN ml_forecast.family_model_assignment_v1 a  ON a.family_name       = s.family_name
LEFT JOIN ml_forecast.model_engine_map_v1        m  ON m.model_code        = COALESCE(a.model_code, s.model_code, 'V4_TWEEDIE_BUNDLE')
LEFT JOIN ml_forecast.class_model_map_v1         cm ON cm.demand_class_final = s.demand_class_final
LEFT JOIN (SELECT famiglia AS family_name, MAX(data) AS max_forecast_date
           FROM public.greenhouse_forecast_results_v2 GROUP BY famiglia) fmax
    ON fmax.family_name = s.family_name
WHERE s.is_active = TRUE
ORDER BY s.business_tier, s.family_name;

-- VERIFICA
DO $$
DECLARE v_assigned BIGINT; v_active BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_assigned FROM ml_forecast.family_model_assignment_v1;
    SELECT COUNT(*) INTO v_active   FROM ml_forecast.family_model_state_v1 WHERE is_active=TRUE;
    RAISE NOTICE '--- BLOCCO B verifica --- assigned=% active=%', v_assigned, v_active;
    IF v_assigned < v_active THEN RAISE WARNING 'Famiglie senza assignment: %', v_active - v_assigned; END IF;
END $$;

COMMIT;
