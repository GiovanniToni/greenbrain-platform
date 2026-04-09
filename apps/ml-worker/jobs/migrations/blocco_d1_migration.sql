-- =============================================================================
-- blocco_d1_migration.sql
-- Blocco D.1 — Semantic cleanup: suggestion strength raw vs effective
-- =============================================================================
-- OBIETTIVO
--   Eliminare l'ambiguità nelle viste suggestion/admin dove
--   suggestion_strength='strong' coesiste con suppression_reason valorizzato.
--
-- MODIFICHE
--   1. v_benchmark_suggestions_status_v1: aggiunte 3 colonne semantiche:
--        suggestion_strength_raw      — forza calcolata dal benchmark (improvement_pct)
--        suggestion_strength_effective — forza realmente utilizzabile (NULL se suppressed)
--        decision_status              — clean | downgraded | suppressed
--
--   2. v_benchmark_admin_v1: propagate le 3 nuove colonne;
--        suggestion_status ora distingue 'suppressed' da 'downgraded'
--
-- INVARIANTI
--   - Tabella base family_model_suggestion_benchmark_v1: NON modificata
--   - family_model_assignment_v1: NON toccata
--   - routing: NON toccato
--   - monitoring D (ml_ops pipeline/family run logs): NON toccato
--   - Colonna suggestion_strength (originale) mantenuta in entrambe le viste
--     per backward compatibility
--
-- SOGLIE BENCHMARK (da benchmark_family.py docstring)
--   improvement_pct >= 10% → 'strong'
--   improvement_pct >=  3% → 'moderate'
--   improvement_pct >=  0% → 'weak'
--   improvement_pct <   0% → 'regression'
--
-- LOGICA suggestion_strength_raw
--   - suppression_reason IS NULL     → stesso valore stored (nessun cap/downgrade)
--   - suppression_reason LIKE 'suppressed_%' → stored value (era già raw prima della soppressione)
--   - altrimenti (downgraded/capped) → ricalcolato da improvement_pct con soglie benchmark
--
-- LOGICA suggestion_strength_effective
--   - 'suppressed_%' → NULL  (holdout troppo sparse, suggerimento non attendibile)
--   - altrimenti     → suggestion_strength stored (già capped/downgraded correttamente)
--
-- LOGICA decision_status
--   - 'suppressed_%' → 'suppressed'
--   - altro IS NOT NULL → 'downgraded'
--   - NULL           → 'clean'
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- STEP 0: Drop dependent views (ordine inverso di dipendenza)
-- v_benchmark_admin_v1 dipende da v_benchmark_suggestions_status_v1
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS ml_ops.v_benchmark_admin_v1;
DROP VIEW IF EXISTS ml_ops.v_benchmark_suggestions_status_v1;

-- -----------------------------------------------------------------------------
-- STEP 1: v_benchmark_suggestions_status_v1
-- Aggiunge: suggestion_strength_raw, suggestion_strength_effective, decision_status
-- Mantiene: tutti i campi originali (backward compat)
-- -----------------------------------------------------------------------------
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
    JOIN ml_forecast.family_benchmark_run_v1 r ON r.run_id = b.run_id
    WHERE b.is_best = TRUE AND r.status = 'done'
    ORDER BY b.family_name, b.competed_at DESC
)
SELECT
    ls.family_name,
    ls.suggested_model_code,
    ls.current_model_code,
    ls.suggested_wmape,
    ls.current_wmape,
    ls.improvement_pct,
    -- original stored value (backward compat)
    -- for suppressed_* rows this is the raw value;
    -- for downgraded/capped rows this is already the post-cap value
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
    ls.benchmark_run_id,

    -- Raw strength: what the benchmark metric alone would yield, before any
    -- quality-based cap, downgrade or suppression.
    -- For suppressed rows: suggestion_strength was never capped, so use as-is.
    -- For downgraded/capped rows: recompute from improvement_pct.
    CASE
        WHEN ls.suppression_reason IS NULL
            THEN ls.suggestion_strength
        WHEN ls.suppression_reason LIKE 'suppressed_%'
            THEN ls.suggestion_strength
        ELSE
            CASE
                WHEN ls.improvement_pct >= 10.0 THEN 'strong'
                WHEN ls.improvement_pct >=  3.0 THEN 'moderate'
                WHEN ls.improvement_pct >=  0.0 THEN 'weak'
                ELSE 'regression'
            END
    END AS suggestion_strength_raw,

    -- Effective strength: the operationally usable signal.
    -- NULL signals "do not act on this suggestion" (fully suppressed).
    CASE
        WHEN ls.suppression_reason LIKE 'suppressed_%' THEN NULL
        ELSE ls.suggestion_strength
    END AS suggestion_strength_effective,

    -- Decision status: single-field operational classification.
    CASE
        WHEN ls.suppression_reason LIKE 'suppressed_%' THEN 'suppressed'
        WHEN ls.suppression_reason IS NOT NULL          THEN 'downgraded'
        ELSE                                                 'clean'
    END AS decision_status

FROM latest_sug ls
LEFT JOIN ml_forecast.family_model_assignment_v1 a
    ON a.family_name = ls.family_name
LEFT JOIN bm_quality bq
    ON bq.family_name = ls.family_name
ORDER BY ls.improvement_pct DESC NULLS LAST, ls.family_name;

COMMENT ON VIEW ml_ops.v_benchmark_suggestions_status_v1 IS
'[Blocco D.1] Suggestion layer con semantica raw/effective/decision.
 suggestion_strength_raw       = forza originale calcolata dall''improvement_pct
 suggestion_strength_effective = forza utilizzabile (NULL se suppressed)
 decision_status               = clean | downgraded | suppressed';

-- -----------------------------------------------------------------------------
-- STEP 2: v_benchmark_admin_v1
-- Propaga i 3 nuovi campi; suggestion_status ora distingue suppressed vs downgraded
-- -----------------------------------------------------------------------------
CREATE VIEW ml_ops.v_benchmark_admin_v1 AS
SELECT
    s.family_name,
    s.demand_class_final,
    a.model_code                        AS assigned_model_code,
    a.is_locked,
    bm.best_model_code,
    bm.best_wmape,
    bm.assigned_wmape,
    bm.improvement_vs_assigned_pct,
    bm.benchmarked_at,
    sug.suggested_model_code,
    -- backward compat (stored, may be post-cap for NZ cases)
    sug.suggestion_strength,
    -- new semantic fields
    sug.suggestion_strength_raw,
    sug.suggestion_strength_effective,
    sug.suppression_reason,
    sug.decision_status,
    sug.improvement_pct                 AS suggestion_improvement_pct,
    sug.holdout_sum_actual,
    sug.holdout_nonzero_days,
    sug.training_nonzero_days,
    CASE
        WHEN sug.suggestion_id IS NOT NULL THEN TRUE
        ELSE FALSE
    END                                 AS has_open_suggestion,
    -- backward compat: TRUE for any modification (downgrade OR suppress)
    CASE
        WHEN sug.suppression_reason IS NOT NULL THEN TRUE
        ELSE FALSE
    END                                 AS is_downgraded,
    -- updated: 6 states, now distinguishes 'suppressed' from 'downgraded'
    CASE
        WHEN sug.suggestion_id IS NOT NULL
             AND sug.suppression_reason IS NULL
            THEN 'clean'
        WHEN sug.suggestion_id IS NOT NULL
             AND sug.suppression_reason LIKE 'suppressed_%'
            THEN 'suppressed'
        WHEN sug.suggestion_id IS NOT NULL
             AND sug.suppression_reason IS NOT NULL
            THEN 'downgraded'
        WHEN bm.best_model_code IS NOT NULL
             AND sug.suggestion_id IS NULL
             AND bm.best_model_code = a.model_code
            THEN 'already_optimal'
        WHEN bm.best_model_code IS NOT NULL
             AND sug.suggestion_id IS NULL
            THEN 'suppressed_or_no_change'
        ELSE 'no_benchmark'
    END                                 AS suggestion_status,
    s.last_train_at,
    s.last_predict_at
FROM ml_forecast.family_model_state_v1 s
LEFT JOIN ml_forecast.family_model_assignment_v1 a
    ON a.family_name = s.family_name
LEFT JOIN ml_ops.v_benchmark_best_model_v1 bm
    ON bm.family_name = s.family_name
LEFT JOIN ml_ops.v_benchmark_suggestions_status_v1 sug
    ON sug.family_name = s.family_name
WHERE s.is_active = TRUE
ORDER BY bm.improvement_vs_assigned_pct DESC NULLS LAST, s.family_name;

COMMENT ON VIEW ml_ops.v_benchmark_admin_v1 IS
'[Blocco D.1] Vista admin con semantica suggestion aggiornata.
 suggestion_status: clean | suppressed | downgraded | already_optimal | suppressed_or_no_change | no_benchmark
 Aggiunto suggestion_strength_raw, suggestion_strength_effective, decision_status.';

-- -----------------------------------------------------------------------------
-- STEP 3: Verifica post-migration
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_ambig_strong   INT;
    v_ambig_eff      INT;
    v_suppressed     INT;
    v_downgraded     INT;
    v_clean          INT;
    v_total_sug      INT;
    v_total_admin    INT;
BEGIN
    -- A: Nessuna riga con effective='strong' E suppression_reason non nulla
    SELECT COUNT(*) INTO v_ambig_strong
    FROM ml_ops.v_benchmark_suggestions_status_v1
    WHERE suggestion_strength_effective = 'strong'
      AND suppression_reason IS NOT NULL;
    IF v_ambig_strong > 0 THEN
        RAISE EXCEPTION 'D.1 CHECK FAILED: % righe con effective=strong + suppression_reason', v_ambig_strong;
    END IF;

    -- B: Ogni riga con decision_status='suppressed' deve avere effective IS NULL
    SELECT COUNT(*) INTO v_ambig_eff
    FROM ml_ops.v_benchmark_suggestions_status_v1
    WHERE decision_status = 'suppressed'
      AND suggestion_strength_effective IS NOT NULL;
    IF v_ambig_eff > 0 THEN
        RAISE EXCEPTION 'D.1 CHECK FAILED: % righe suppressed con effective non NULL', v_ambig_eff;
    END IF;

    -- C: raw deve essere sempre valorizzato (non NULL)
    SELECT COUNT(*) INTO v_ambig_strong
    FROM ml_ops.v_benchmark_suggestions_status_v1
    WHERE suggestion_strength_raw IS NULL;
    IF v_ambig_strong > 0 THEN
        RAISE EXCEPTION 'D.1 CHECK FAILED: % righe con suggestion_strength_raw IS NULL', v_ambig_strong;
    END IF;

    -- Distribution
    SELECT COUNT(*) INTO v_total_sug   FROM ml_ops.v_benchmark_suggestions_status_v1;
    SELECT COUNT(*) INTO v_total_admin FROM ml_ops.v_benchmark_admin_v1;
    SELECT COUNT(*) INTO v_suppressed  FROM ml_ops.v_benchmark_admin_v1 WHERE suggestion_status = 'suppressed';
    SELECT COUNT(*) INTO v_downgraded  FROM ml_ops.v_benchmark_admin_v1 WHERE suggestion_status = 'downgraded';
    SELECT COUNT(*) INTO v_clean       FROM ml_ops.v_benchmark_admin_v1 WHERE suggestion_status = 'clean';

    RAISE NOTICE 'D.1 MIGRATION OK';
    RAISE NOTICE '  v_benchmark_suggestions_status_v1 : % open suggestions', v_total_sug;
    RAISE NOTICE '  v_benchmark_admin_v1              : % active families',  v_total_admin;
    RAISE NOTICE '  suggestion_status distribution    : clean=%, downgraded=%, suppressed=%',
        v_clean, v_downgraded, v_suppressed;
END;
$$;

COMMIT;
