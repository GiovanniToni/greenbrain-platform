-- BLOCCO C: Benchmark + auto model selection (suggestion only) — 2026-03-13
-- Idempotente: sicuro da rieseguire

BEGIN;

-- STEP 0: Backup model_catalog_v1 stato pre-BLOCCO C
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema='ml_forecast' AND table_name='_bak_model_catalog_v1_c_20260313') THEN
        CREATE TABLE ml_forecast._bak_model_catalog_v1_c_20260313 AS
            SELECT * FROM ml_forecast.model_catalog_v1;
        RAISE NOTICE 'Backup model_catalog_v1 salvato';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema='ml_forecast' AND table_name='_bak_suggestion_bm_v1_c_20260313') THEN
        CREATE TABLE ml_forecast._bak_suggestion_bm_v1_c_20260313 AS
            SELECT * FROM ml_forecast.family_model_suggestion_benchmark_v1;
        RAISE NOTICE 'Backup suggestion_benchmark_v1 salvato';
    END IF;
END $$;

-- STEP 1: Aggiunge campi governance benchmark a model_catalog_v1
ALTER TABLE ml_forecast.model_catalog_v1
    ADD COLUMN IF NOT EXISTS is_active         BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS benchmark_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS supports_backtest BOOLEAN NOT NULL DEFAULT TRUE;

-- V4_TWEEDIE_BUNDLE è LightGBM subprocess → benchmark offline non supportato
UPDATE ml_forecast.model_catalog_v1
SET supports_backtest = FALSE
WHERE model_code = 'V4_TWEEDIE_BUNDLE';

-- STEP 2: Tabella benchmark run (una riga per esecuzione benchmark)
CREATE TABLE IF NOT EXISTS ml_forecast.family_benchmark_run_v1 (
    run_id          BIGSERIAL PRIMARY KEY,
    triggered_by    TEXT    NOT NULL DEFAULT 'manual',
    scope           TEXT,                           -- 'one','many','new','all'
    scope_detail    TEXT,                           -- famiglia/classe/filtro usato
    holdout_days    INT     NOT NULL DEFAULT 10,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at     TIMESTAMPTZ,
    status          TEXT    NOT NULL DEFAULT 'running',  -- 'running','done','failed'
    families_total  INT     DEFAULT 0,
    families_done   INT     DEFAULT 0,
    models_tested   INT     DEFAULT 0,
    error_message   TEXT,
    notes           TEXT
);

-- STEP 3: Tabella risultati benchmark per-famiglia per-modello
CREATE TABLE IF NOT EXISTS ml_forecast.family_model_benchmark_v1 (
    benchmark_id    BIGSERIAL PRIMARY KEY,
    run_id          BIGINT REFERENCES ml_forecast.family_benchmark_run_v1(run_id) ON DELETE CASCADE,
    family_name     TEXT    NOT NULL,
    model_code      TEXT    NOT NULL REFERENCES ml_forecast.model_catalog_v1(model_code),
    holdout_days    INT     NOT NULL DEFAULT 10,
    holdout_start   DATE,
    holdout_end     DATE,
    train_rows      INT,
    test_rows       INT,
    wmape           NUMERIC(10,4),  -- metrica primaria
    mae             NUMERIC(10,4),
    rmse            NUMERIC(10,4),
    bias            NUMERIC(10,4),
    is_best         BOOLEAN NOT NULL DEFAULT FALSE,
    competed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    notes           TEXT,
    UNIQUE (run_id, family_name, model_code)
);

CREATE INDEX IF NOT EXISTS idx_bm_v1_family_name
    ON ml_forecast.family_model_benchmark_v1(family_name);
CREATE INDEX IF NOT EXISTS idx_bm_v1_run_id
    ON ml_forecast.family_model_benchmark_v1(run_id);
CREATE INDEX IF NOT EXISTS idx_bm_v1_is_best
    ON ml_forecast.family_model_benchmark_v1(family_name, is_best) WHERE is_best = TRUE;

-- STEP 4: Aggiunge campi mancanti a family_model_suggestion_benchmark_v1
ALTER TABLE ml_forecast.family_model_suggestion_benchmark_v1
    ADD COLUMN IF NOT EXISTS is_best                  BOOLEAN  NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS suggestion_strength      TEXT,
    ADD COLUMN IF NOT EXISTS min_improvement_threshold NUMERIC(6,2) DEFAULT 3.0;

-- Aggiorna default error_metric a WMAPE per nuove righe
ALTER TABLE ml_forecast.family_model_suggestion_benchmark_v1
    ALTER COLUMN error_metric SET DEFAULT 'WMAPE';

-- STEP 5: Vista — miglior modello per famiglia (da run più recente completato)
CREATE OR REPLACE VIEW ml_ops.v_benchmark_best_model_v1 AS
WITH latest_run AS (
    SELECT DISTINCT ON (b.family_name)
        b.family_name,
        b.model_code      AS best_model_code,
        b.wmape           AS best_wmape,
        b.mae             AS best_mae,
        b.run_id,
        r.started_at      AS benchmarked_at,
        b.holdout_days
    FROM ml_forecast.family_model_benchmark_v1 b
    JOIN ml_forecast.family_benchmark_run_v1   r ON r.run_id = b.run_id
    WHERE b.is_best = TRUE AND r.status = 'done'
    ORDER BY b.family_name, r.started_at DESC
),
assigned_perf AS (
    SELECT b.family_name, b.model_code, b.wmape AS assigned_wmape, b.run_id
    FROM ml_forecast.family_model_benchmark_v1 b
    WHERE EXISTS (
        SELECT 1 FROM ml_forecast.family_model_assignment_v1 a
        WHERE a.family_name = b.family_name AND a.model_code = b.model_code
    )
)
SELECT
    lr.family_name,
    lr.best_model_code,
    lr.best_wmape,
    lr.best_mae,
    lr.benchmarked_at,
    lr.holdout_days,
    a.model_code     AS assigned_model_code,
    ap.assigned_wmape,
    CASE WHEN ap.assigned_wmape > 0 THEN
        ROUND(((ap.assigned_wmape - lr.best_wmape) / ap.assigned_wmape) * 100.0, 2)
    ELSE NULL END    AS improvement_vs_assigned_pct,
    lr.run_id
FROM latest_run lr
LEFT JOIN ml_forecast.family_model_assignment_v1   a  ON a.family_name  = lr.family_name
LEFT JOIN assigned_perf                            ap ON ap.family_name = lr.family_name
                                                     AND ap.run_id     = lr.run_id;

-- STEP 6: Vista — run recenti benchmark
CREATE OR REPLACE VIEW ml_ops.v_benchmark_recent_runs_v1 AS
SELECT
    r.run_id,
    r.scope,
    r.scope_detail,
    r.holdout_days,
    r.status,
    r.families_total,
    r.families_done,
    r.models_tested,
    r.started_at,
    r.finished_at,
    ROUND(EXTRACT(EPOCH FROM (COALESCE(r.finished_at, now()) - r.started_at)) / 60.0, 1) AS duration_min,
    r.triggered_by,
    r.notes
FROM ml_forecast.family_benchmark_run_v1 r
ORDER BY r.started_at DESC
LIMIT 50;

-- STEP 7: Vista — suggerimenti aperti per famiglia (ultimi non ancora applicati)
CREATE OR REPLACE VIEW ml_ops.v_benchmark_suggestions_status_v1 AS
WITH latest_sug AS (
    SELECT DISTINCT ON (s.family_name)
        s.suggestion_id,
        s.family_name,
        s.model_code           AS suggested_model_code,
        s.competitor_model_code AS current_model_code,
        s.error_metric,
        s.error_value          AS suggested_wmape,
        s.competitor_error_value AS current_wmape,
        s.improvement_pct,
        s.suggestion_strength,
        s.is_best,
        s.is_applied,
        s.suggested_at
    FROM ml_forecast.family_model_suggestion_benchmark_v1 s
    WHERE s.is_applied = FALSE
    ORDER BY s.family_name, s.suggested_at DESC
)
SELECT
    ls.family_name,
    ls.suggested_model_code,
    ls.current_model_code,
    ls.suggested_wmape,
    ls.current_wmape,
    ls.improvement_pct,
    ls.suggestion_strength,
    ls.is_best,
    a.is_locked,
    ls.suggested_at,
    ls.suggestion_id
FROM latest_sug ls
LEFT JOIN ml_forecast.family_model_assignment_v1 a ON a.family_name = ls.family_name
ORDER BY ls.improvement_pct DESC NULLS LAST, ls.family_name;

-- STEP 8: Vista admin comprensiva benchmark
CREATE OR REPLACE VIEW ml_ops.v_benchmark_admin_v1 AS
SELECT
    s.family_name,
    s.business_tier,
    s.demand_class_final,
    a.model_code                                  AS assigned_model_code,
    bm.best_model_code,
    bm.best_wmape,
    bm.assigned_wmape,
    bm.improvement_vs_assigned_pct,
    bm.benchmarked_at,
    sug.suggested_model_code,
    sug.suggestion_strength,
    sug.improvement_pct                           AS suggestion_improvement_pct,
    a.is_locked,
    CASE WHEN sug.suggestion_id IS NOT NULL THEN TRUE ELSE FALSE END AS has_open_suggestion,
    s.last_train_at,
    s.last_predict_at
FROM ml_forecast.family_model_state_v1              s
LEFT JOIN ml_forecast.family_model_assignment_v1    a   ON a.family_name   = s.family_name
LEFT JOIN ml_ops.v_benchmark_best_model_v1          bm  ON bm.family_name  = s.family_name
LEFT JOIN ml_ops.v_benchmark_suggestions_status_v1  sug ON sug.family_name = s.family_name
WHERE s.is_active = TRUE
ORDER BY bm.improvement_vs_assigned_pct DESC NULLS LAST, s.family_name;

DO $$
BEGIN
    RAISE NOTICE '--- BLOCCO C verifica ---';
    RAISE NOTICE 'model_catalog_v1: benchmark_enabled e supports_backtest aggiunti';
    RAISE NOTICE 'family_benchmark_run_v1: creata';
    RAISE NOTICE 'family_model_benchmark_v1: creata';
    RAISE NOTICE 'suggestion_benchmark_v1: is_best, suggestion_strength aggiunti';
    RAISE NOTICE 'Viste: v_benchmark_best_model_v1, v_benchmark_recent_runs_v1,';
    RAISE NOTICE '       v_benchmark_suggestions_status_v1, v_benchmark_admin_v1';
END $$;

COMMIT;
