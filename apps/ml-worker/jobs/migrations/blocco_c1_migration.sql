-- BLOCCO C.1: Deduplication + Anti-False-Positive NAIVE_ZERO + Data Quality Fields
-- Data: 2026-03-14  (rev 2 — fix CREATE OR REPLACE VIEW column-order error)
-- Idempotente: sicuro da rieseguire
-- Prerequisiti: blocco_c_migration.sql già applicato
--
-- FIX vs rev 1:
--   CREATE OR REPLACE VIEW fallisce quando cambia l'ordine/nome delle colonne
--   esistenti (errore PG: "cannot change name of view column").
--   Soluzione: DROP VIEW nell'ordine delle dipendenze, poi CREATE VIEW.
--   Ordine drop: v_benchmark_admin_v1 (dipende da suggestions_status)
--              → v_benchmark_suggestions_status_v1

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 0: Backup suggestion table stato pre-C.1 (solo alla prima esecuzione)
-- ──────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'ml_forecast'
          AND table_name   = '_bak_suggestion_bm_c1_pre'
    ) THEN
        CREATE TABLE ml_forecast._bak_suggestion_bm_c1_pre
            AS SELECT * FROM ml_forecast.family_model_suggestion_benchmark_v1;
        RAISE NOTICE 'Backup suggestion_benchmark_v1 pre-C.1 salvato';
    ELSE
        RAISE NOTICE 'Backup _bak_suggestion_bm_c1_pre già esistente, salto';
    END IF;
END $$;


-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 1: Aggiungi campi qualità holdout a family_model_benchmark_v1
-- ──────────────────────────────────────────────────────────────────────────────

ALTER TABLE ml_forecast.family_model_benchmark_v1
    ADD COLUMN IF NOT EXISTS holdout_sum_actual    NUMERIC(14,4),
    ADD COLUMN IF NOT EXISTS holdout_nonzero_days  INT,
    ADD COLUMN IF NOT EXISTS training_sum_actual   NUMERIC(14,4),
    ADD COLUMN IF NOT EXISTS training_nonzero_days INT;


-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 2: Aggiungi suppression_reason a suggestion table
-- ──────────────────────────────────────────────────────────────────────────────

ALTER TABLE ml_forecast.family_model_suggestion_benchmark_v1
    ADD COLUMN IF NOT EXISTS suppression_reason TEXT;


-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 3: Cleanup duplicati aperti
-- Tieni solo il suggestion_id più recente per famiglia (is_applied=FALSE).
-- Le suggestion applicate (is_applied=TRUE) sono intoccate.
-- ──────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_deleted INT;
BEGIN
    WITH keep AS (
        SELECT MAX(suggestion_id) AS keep_id
        FROM ml_forecast.family_model_suggestion_benchmark_v1
        WHERE is_applied = FALSE
        GROUP BY family_name
    )
    DELETE FROM ml_forecast.family_model_suggestion_benchmark_v1
    WHERE is_applied = FALSE
      AND suggestion_id NOT IN (SELECT keep_id FROM keep);

    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RAISE NOTICE 'STEP 3: Eliminati % suggestion duplicati aperti', v_deleted;
END $$;


-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 4: Rimuovi vecchio indice ridondante (sostituito da quello unico)
-- ──────────────────────────────────────────────────────────────────────────────

DROP INDEX IF EXISTS ml_forecast.ix_suggestion_benchmark_unapplied;


-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 5: Indice unico parziale — max 1 suggestion aperta per famiglia
-- Prerequisito: STEP 3 già eseguito (zero duplicati aperti)
-- ──────────────────────────────────────────────────────────────────────────────

CREATE UNIQUE INDEX IF NOT EXISTS ux_suggestion_one_open_per_family
    ON ml_forecast.family_model_suggestion_benchmark_v1 (family_name)
    WHERE (is_applied = FALSE);


-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 6: Rimuovi viste nell'ordine delle dipendenze
--
-- v_benchmark_admin_v1 dipende da v_benchmark_suggestions_status_v1
-- → admin va droppata PRIMA di suggestions_status
-- v_benchmark_best_model_v1 non ha cambiamenti C.1 → non va toccata
-- ──────────────────────────────────────────────────────────────────────────────

DROP VIEW IF EXISTS ml_ops.v_benchmark_admin_v1;
DROP VIEW IF EXISTS ml_ops.v_benchmark_suggestions_status_v1;


-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 7: Ricrea v_benchmark_suggestions_status_v1 con colonne C.1
-- ──────────────────────────────────────────────────────────────────────────────

CREATE VIEW ml_ops.v_benchmark_suggestions_status_v1 AS
WITH latest_sug AS (
    SELECT DISTINCT ON (s.family_name)
        s.suggestion_id,
        s.family_name,
        s.model_code                AS suggested_model_code,
        s.competitor_model_code     AS current_model_code,
        s.error_metric,
        s.error_value               AS suggested_wmape,
        s.competitor_error_value    AS current_wmape,
        s.improvement_pct,
        s.suggestion_strength,
        s.suppression_reason,
        s.is_best,
        s.is_applied,
        s.benchmark_run_id,
        s.suggested_at
    FROM ml_forecast.family_model_suggestion_benchmark_v1 s
    WHERE s.is_applied = FALSE
    ORDER BY s.family_name, s.suggested_at DESC
),
bm_quality AS (
    SELECT DISTINCT ON (b.family_name)
        b.family_name,
        b.holdout_sum_actual,
        b.holdout_nonzero_days,
        b.training_nonzero_days,
        b.training_sum_actual
    FROM ml_forecast.family_model_benchmark_v1 b
    JOIN ml_forecast.family_benchmark_run_v1   r ON r.run_id = b.run_id
    WHERE b.is_best = TRUE
      AND r.status  = 'done'
    ORDER BY b.family_name, b.competed_at DESC
)
SELECT
    ls.family_name,
    ls.suggested_model_code,
    ls.current_model_code,
    ls.suggested_wmape,
    ls.current_wmape,
    ls.improvement_pct,
    ls.suggestion_strength,
    ls.suppression_reason,
    ls.is_best,
    bq.holdout_sum_actual,
    bq.holdout_nonzero_days,
    bq.training_nonzero_days,
    bq.training_sum_actual,
    a.is_locked,
    ls.suggested_at,
    ls.suggestion_id,
    ls.benchmark_run_id
FROM latest_sug ls
LEFT JOIN ml_forecast.family_model_assignment_v1 a  ON a.family_name  = ls.family_name
LEFT JOIN bm_quality                             bq ON bq.family_name = ls.family_name
ORDER BY ls.improvement_pct DESC NULLS LAST, ls.family_name;


-- ──────────────────────────────────────────────────────────────────────────────
-- STEP 8: Ricrea v_benchmark_admin_v1 con colonne C.1 + suggestion_status
-- ──────────────────────────────────────────────────────────────────────────────

CREATE VIEW ml_ops.v_benchmark_admin_v1 AS
SELECT
    s.family_name,
    s.business_tier,
    s.demand_class_final,
    a.model_code                                            AS assigned_model_code,
    a.is_locked,
    bm.best_model_code,
    bm.best_wmape,
    bm.assigned_wmape,
    bm.improvement_vs_assigned_pct,
    bm.benchmarked_at,
    sug.suggested_model_code,
    sug.suggestion_strength,
    sug.suppression_reason,
    sug.improvement_pct                                     AS suggestion_improvement_pct,
    sug.holdout_sum_actual,
    sug.holdout_nonzero_days,
    sug.training_nonzero_days,
    CASE WHEN sug.suggestion_id IS NOT NULL THEN TRUE
         ELSE FALSE END                                     AS has_open_suggestion,
    CASE WHEN sug.suppression_reason IS NOT NULL THEN TRUE
         ELSE FALSE END                                     AS is_downgraded,
    CASE
        WHEN sug.suggestion_id IS NOT NULL AND sug.suppression_reason IS NULL
            THEN 'clean'
        WHEN sug.suggestion_id IS NOT NULL AND sug.suppression_reason IS NOT NULL
            THEN 'downgraded'
        WHEN bm.best_model_code IS NOT NULL
             AND sug.suggestion_id IS NULL
             AND bm.best_model_code = a.model_code
            THEN 'already_optimal'
        WHEN bm.best_model_code IS NOT NULL AND sug.suggestion_id IS NULL
            THEN 'suppressed_or_no_change'
        ELSE 'no_benchmark'
    END                                                     AS suggestion_status,
    s.last_train_at,
    s.last_predict_at
FROM ml_forecast.family_model_state_v1              s
LEFT JOIN ml_forecast.family_model_assignment_v1    a   ON a.family_name   = s.family_name
LEFT JOIN ml_ops.v_benchmark_best_model_v1          bm  ON bm.family_name  = s.family_name
LEFT JOIN ml_ops.v_benchmark_suggestions_status_v1  sug ON sug.family_name = s.family_name
WHERE s.is_active = TRUE
ORDER BY bm.improvement_vs_assigned_pct DESC NULLS LAST, s.family_name;


-- ──────────────────────────────────────────────────────────────────────────────
-- VERIFICA FINALE (errore bloccante se fallisce)
-- ──────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_open_sug      INT;
    v_families_sug  INT;
    v_idx_exists    BOOLEAN;
    v_col_bm        INT;
    v_col_sug       INT;
BEGIN
    -- Nessun duplicato aperto
    SELECT COUNT(*) INTO v_open_sug
    FROM ml_forecast.family_model_suggestion_benchmark_v1
    WHERE is_applied = FALSE;

    SELECT COUNT(DISTINCT family_name) INTO v_families_sug
    FROM ml_forecast.family_model_suggestion_benchmark_v1
    WHERE is_applied = FALSE;

    IF v_open_sug != v_families_sug THEN
        RAISE EXCEPTION 'ERRORE: % suggestion aperte su % famiglie → duplicati ancora presenti!',
            v_open_sug, v_families_sug;
    END IF;

    -- Indice unico presente
    SELECT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'ml_forecast'
          AND indexname  = 'ux_suggestion_one_open_per_family'
    ) INTO v_idx_exists;

    IF NOT v_idx_exists THEN
        RAISE EXCEPTION 'ERRORE: indice ux_suggestion_one_open_per_family non trovato';
    END IF;

    -- Colonne C.1 su benchmark_v1
    SELECT COUNT(*) INTO v_col_bm
    FROM information_schema.columns
    WHERE table_schema = 'ml_forecast'
      AND table_name   = 'family_model_benchmark_v1'
      AND column_name  IN ('holdout_sum_actual','holdout_nonzero_days',
                           'training_sum_actual','training_nonzero_days');

    IF v_col_bm < 4 THEN
        RAISE EXCEPTION 'ERRORE: colonne holdout/training mancanti in family_model_benchmark_v1 (trovate %/4)', v_col_bm;
    END IF;

    -- Colonna suppression_reason su suggestion
    SELECT COUNT(*) INTO v_col_sug
    FROM information_schema.columns
    WHERE table_schema = 'ml_forecast'
      AND table_name   = 'family_model_suggestion_benchmark_v1'
      AND column_name  = 'suppression_reason';

    IF v_col_sug < 1 THEN
        RAISE EXCEPTION 'ERRORE: colonna suppression_reason mancante in family_model_suggestion_benchmark_v1';
    END IF;

    RAISE NOTICE '--- BLOCCO C.1 verifica OK ---';
    RAISE NOTICE 'Colonne benchmark_v1 C.1: 4/4 presenti';
    RAISE NOTICE 'Colonna suppression_reason: presente';
    RAISE NOTICE 'Suggestion aperte: % (% famiglie uniche) — nessun duplicato', v_open_sug, v_families_sug;
    RAISE NOTICE 'Indice ux_suggestion_one_open_per_family: presente';
    RAISE NOTICE 'Viste: v_benchmark_suggestions_status_v1, v_benchmark_admin_v1 ricostruite';
    RAISE NOTICE '--- Fine BLOCCO C.1 ---';
END $$;

COMMIT;
