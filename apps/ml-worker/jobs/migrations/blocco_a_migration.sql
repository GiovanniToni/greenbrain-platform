-- =============================================================
-- BLOCCO A: Governance robusta modelli forecast
-- Data: 2026-03-13
-- Idempotente: sicuro da rieseguire
-- =============================================================

BEGIN;

-- =============================================================
-- STEP 0: Backup strutture toccate (solo se non esistono già)
-- =============================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'ml_forecast'
          AND table_name   = '_bak_model_catalog_v1_20260313'
    ) THEN
        CREATE TABLE ml_forecast._bak_model_catalog_v1_20260313
            AS SELECT * FROM ml_forecast.model_catalog_v1;
        RAISE NOTICE 'Backup: _bak_model_catalog_v1_20260313 creato';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'ml_forecast'
          AND table_name   = '_bak_model_engine_map_v1_20260313'
    ) THEN
        CREATE TABLE ml_forecast._bak_model_engine_map_v1_20260313
            AS SELECT * FROM ml_forecast.model_engine_map_v1;
        RAISE NOTICE 'Backup: _bak_model_engine_map_v1_20260313 creato';
    END IF;
END $$;


-- =============================================================
-- STEP 1: model_catalog_v1 — aggiungere V4_TWEEDIE_BUNDLE
-- =============================================================

INSERT INTO ml_forecast.model_catalog_v1 (
    model_code,
    model_name,
    model_family,
    model_priority,
    is_seasonal,
    is_intermittent,
    default_horizon_days,
    update_frequency,
    notes
) VALUES (
    'V4_TWEEDIE_BUNDLE',
    'LightGBM Tweedie Bundle v4',
    'bundle',
    0,
    true,
    false,
    10,
    'biweekly',
    'Default ML bundle. Subprocess-based. Fallback per famiglie senza assignment esplicito.'
)
ON CONFLICT (model_code) DO NOTHING;

-- Allineare default_horizon_days = 10 per tutti i modelli
-- (coerente con i parametri ENV dei singoli engine Python)
UPDATE ml_forecast.model_catalog_v1
SET default_horizon_days = 10
WHERE default_horizon_days != 10;


-- =============================================================
-- STEP 2: model_engine_map_v1 — aggiungere V4_TWEEDIE_BUNDLE
--         e sistemare rollout_stage incoerenti
-- =============================================================

INSERT INTO ml_forecast.model_engine_map_v1 (
    model_code,
    target_execution_engine,
    current_execution_engine,
    rollout_stage,
    notes
) VALUES (
    'V4_TWEEDIE_BUNDLE',
    'V4_TWEEDIE_BUNDLE',
    'V4_TWEEDIE_BUNDLE',
    'stable',
    'Default legacy bundle. Eseguito come subprocess esterno.'
)
ON CONFLICT (model_code) DO NOTHING;

-- rollout_stage 'test_*' → 'stable': tutti gli engine sono verificati in produzione
UPDATE ml_forecast.model_engine_map_v1
SET rollout_stage = 'stable'
WHERE rollout_stage LIKE 'test_%';

-- SEASONAL_CROSTON_SBA era 'planned': ora implementato e attivo
UPDATE ml_forecast.model_engine_map_v1
SET rollout_stage = 'stable'
WHERE model_code = 'SEASONAL_CROSTON_SBA'
  AND rollout_stage IN ('planned', 'active', 'test');


-- =============================================================
-- STEP 3: family_model_assignment_v1
--         La fonte autoritativa di override manuale per famiglia.
--         NON contiene execution_engine: si deriva sempre da model_engine_map_v1.
-- =============================================================

CREATE TABLE IF NOT EXISTS ml_forecast.family_model_assignment_v1 (
    family_name       TEXT        NOT NULL,
    model_code        TEXT        NOT NULL,
    is_locked         BOOLEAN     NOT NULL DEFAULT FALSE,
    assigned_by       TEXT        NOT NULL DEFAULT 'system',
    assigned_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    assignment_reason TEXT,
    notes             TEXT,
    CONSTRAINT pk_family_model_assignment_v1
        PRIMARY KEY (family_name),
    CONSTRAINT fk_assignment_model_code
        FOREIGN KEY (model_code)
        REFERENCES ml_forecast.model_catalog_v1 (model_code)
);

CREATE INDEX IF NOT EXISTS ix_family_model_assignment_locked
    ON ml_forecast.family_model_assignment_v1 (is_locked)
    WHERE is_locked = TRUE;


-- =============================================================
-- STEP 4: family_model_assignment_log_v1
--         Log immutabile di ogni cambio di assignment.
-- =============================================================

CREATE TABLE IF NOT EXISTS ml_forecast.family_model_assignment_log_v1 (
    log_id          BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    family_name     TEXT        NOT NULL,
    old_model_code  TEXT,
    new_model_code  TEXT        NOT NULL,
    old_is_locked   BOOLEAN,
    new_is_locked   BOOLEAN,
    changed_by      TEXT        NOT NULL DEFAULT 'system',
    pipeline_run_id BIGINT,
    changed_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    reason          TEXT
);

CREATE INDEX IF NOT EXISTS ix_assignment_log_family_at
    ON ml_forecast.family_model_assignment_log_v1 (family_name, changed_at DESC);


-- =============================================================
-- STEP 5: family_model_suggestion_classification_v1
--         Suggerimenti derivati dalla classificazione della domanda.
-- =============================================================

CREATE TABLE IF NOT EXISTS ml_forecast.family_model_suggestion_classification_v1 (
    family_name            TEXT        NOT NULL,
    model_code             TEXT        NOT NULL,
    demand_class           TEXT        NOT NULL,
    classification_version TEXT,
    suggested_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_applied             BOOLEAN     NOT NULL DEFAULT FALSE,
    applied_at             TIMESTAMPTZ,
    notes                  TEXT,
    CONSTRAINT pk_suggestion_classification_v1
        PRIMARY KEY (family_name),
    CONSTRAINT fk_suggestion_class_model
        FOREIGN KEY (model_code)
        REFERENCES ml_forecast.model_catalog_v1 (model_code)
);


-- =============================================================
-- STEP 6: family_model_suggestion_benchmark_v1
--         Suggerimenti derivati da benchmark empirici.
--         Struttura separata: metadati incompatibili con classification.
-- =============================================================

CREATE TABLE IF NOT EXISTS ml_forecast.family_model_suggestion_benchmark_v1 (
    suggestion_id          BIGINT  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    family_name            TEXT    NOT NULL,
    model_code             TEXT    NOT NULL,
    benchmark_run_id       BIGINT,
    error_metric           TEXT    NOT NULL DEFAULT 'MAE',
    error_value            NUMERIC,
    competitor_model_code  TEXT,
    competitor_error_value NUMERIC,
    improvement_pct        NUMERIC,
    suggested_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_applied             BOOLEAN     NOT NULL DEFAULT FALSE,
    applied_at             TIMESTAMPTZ,
    notes                  TEXT,
    CONSTRAINT fk_suggestion_benchmark_model
        FOREIGN KEY (model_code)
        REFERENCES ml_forecast.model_catalog_v1 (model_code)
);

CREATE INDEX IF NOT EXISTS ix_suggestion_benchmark_family_at
    ON ml_forecast.family_model_suggestion_benchmark_v1 (family_name, suggested_at DESC);

CREATE INDEX IF NOT EXISTS ix_suggestion_benchmark_unapplied
    ON ml_forecast.family_model_suggestion_benchmark_v1 (family_name)
    WHERE is_applied = FALSE;


-- =============================================================
-- STEP 7: v_family_execution_routing_v2
--
-- Priorità effective_model_code:
--   1. family_model_assignment_v1  (override manuale esplicito)
--   2. family_model_registry_v2    (da classificazione)
--   3. fallback hardcoded          → V4_TWEEDIE_BUNDLE
--
-- La logica di priorità sta nella vista SQL — i router Python
-- leggono solo effective_execution_engine e routing_source.
--
-- Colonne backward-compatible con v1:
--   family_name, business_tier, demand_class_final, model_code,
--   registry_execution_engine, registry_bundle_version,
--   target_execution_engine, current_execution_engine,
--   effective_execution_engine, routing_source,
--   is_active, needs_initial_train, needs_retrain, needs_predict,
--   last_train_at, last_predict_at, last_train_status, last_predict_status
-- =============================================================

CREATE OR REPLACE VIEW ml_forecast.v_family_execution_routing_v2 AS
WITH base AS (
    SELECT
        r.family_name,
        r.business_tier,
        r.demand_class_final,
        r.model_code                                                       AS registry_model_code,
        r.execution_engine                                                 AS registry_execution_engine,
        r.bundle_version                                                   AS registry_bundle_version,
        a.model_code                                                       AS assignment_model_code,
        COALESCE(a.is_locked, FALSE)                                       AS is_locked,
        a.assigned_by,
        -- effective_model_code: assignment > registry (class) > fallback
        COALESCE(a.model_code, r.model_code, 'V4_TWEEDIE_BUNDLE')         AS effective_model_code,
        CASE
            WHEN a.model_code IS NOT NULL THEN 'manual_assignment'
            WHEN r.model_code IS NOT NULL THEN 'class_map'
            ELSE 'fallback_v4'
        END                                                                AS routing_source,
        s.is_active,
        s.needs_initial_train,
        s.needs_retrain,
        s.needs_predict,
        s.last_train_at,
        s.last_predict_at,
        s.last_train_status,
        s.last_predict_status
    FROM      ml_forecast.family_model_registry_v2      r
    LEFT JOIN ml_forecast.family_model_state_v1          s  ON s.family_name = r.family_name
    LEFT JOIN ml_forecast.family_model_assignment_v1     a  ON a.family_name = r.family_name
)
SELECT
    b.family_name,
    b.business_tier,
    b.demand_class_final,
    -- model_code esposto come effective (compat v1: i router usano model_code)
    b.effective_model_code                                                 AS model_code,
    b.registry_model_code,
    b.assignment_model_code,
    b.is_locked,
    b.assigned_by,
    b.routing_source,
    b.registry_execution_engine,
    b.registry_bundle_version,
    m.current_execution_engine,
    m.target_execution_engine,
    -- effective_execution_engine: engine attivo → altrimenti fallback V4
    CASE
        WHEN ec.is_active = TRUE THEN m.current_execution_engine
        ELSE 'V4_TWEEDIE_BUNDLE'
    END                                                                    AS effective_execution_engine,
    b.is_active,
    b.needs_initial_train,
    b.needs_retrain,
    b.needs_predict,
    b.last_train_at,
    b.last_predict_at,
    b.last_train_status,
    b.last_predict_status
FROM base b
LEFT JOIN ml_forecast.model_engine_map_v1         m  ON m.model_code        = b.effective_model_code
LEFT JOIN ml_forecast.execution_engine_catalog_v1 ec ON ec.execution_engine = m.current_execution_engine;


-- =============================================================
-- STEP 8: Popolare job_schedule_config_v1 con i job principali
-- =============================================================

INSERT INTO ml_ops.job_schedule_config_v1 (
    job_type,
    is_enabled,
    schedule_kind,
    schedule_note,
    max_runtime_minutes
) VALUES
    ('predict_daily',          TRUE,  'systemd', 'Predict giornaliero via systemd timer',               120),
    ('train_biweekly_all',     TRUE,  'systemd', 'Train completo bisettimanale via systemd timer',      480),
    ('train_missing',          TRUE,  'systemd', 'Train bundle mancanti su ciclo periodico',             240),
    ('benchmark_weekly',       FALSE, 'manual',  'Benchmark settimanale (disabilitato, non ancora impl)', 360),
    ('classification_refresh', TRUE,  'systemd', 'Aggiornamento classificazione su nuovi dati',          60)
ON CONFLICT (job_type) DO NOTHING;


-- =============================================================
-- VERIFICA FINALE (non bloccante)
-- =============================================================

DO $$
DECLARE
    v_count_catalog     INT;
    v_count_engine_map  INT;
    v_count_routing_v2  INT;
BEGIN
    SELECT COUNT(*) INTO v_count_catalog    FROM ml_forecast.model_catalog_v1;
    SELECT COUNT(*) INTO v_count_engine_map FROM ml_forecast.model_engine_map_v1;
    SELECT COUNT(*) INTO v_count_routing_v2 FROM ml_forecast.v_family_execution_routing_v2 LIMIT 1;

    RAISE NOTICE '--- BLOCCO A verifica ---';
    RAISE NOTICE 'model_catalog_v1 righe:    %', v_count_catalog;
    RAISE NOTICE 'model_engine_map_v1 righe: %', v_count_engine_map;

    IF NOT EXISTS (SELECT 1 FROM ml_forecast.model_catalog_v1 WHERE model_code = 'V4_TWEEDIE_BUNDLE') THEN
        RAISE EXCEPTION 'ERRORE: V4_TWEEDIE_BUNDLE mancante da model_catalog_v1';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ml_forecast.model_engine_map_v1 WHERE model_code = 'V4_TWEEDIE_BUNDLE') THEN
        RAISE EXCEPTION 'ERRORE: V4_TWEEDIE_BUNDLE mancante da model_engine_map_v1';
    END IF;

    RAISE NOTICE 'Verifica OK: V4_TWEEDIE_BUNDLE presente in catalog e engine_map';
    RAISE NOTICE 'v_family_execution_routing_v2 accessibile';
    RAISE NOTICE '--- Fine BLOCCO A ---';
END $$;

COMMIT;
