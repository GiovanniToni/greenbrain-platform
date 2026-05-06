-- =============================================================================
-- blocco_g_migration.sql
-- Blocco G — Finalizzazione: drop tabelle _bak_ e legacy vuote in ml_forecast
-- =============================================================================
-- OGGETTI RIMOSSI
--   15 tabelle _bak_*: snapshot migration Mar 10-13, pg_depend=0, 1.72MB totali
--   1 tabella legacy vuota: family_model_suggestion_classification_v1 (0 righe, 0 deps)
--
-- MARCATURE DEPRECATE
--   v_family_model_registry_v1: usa family_model_registry_v1 (old table),
--     non chiamata da codice Python attivo (solo validate_engines.py usa routing_v1,
--     non registry_v1). Tenuta per compatibilità ma marcata deprecated.
--
-- INVARIANTI GARANTITI
--   family_model_assignment_v1 = 844
--   v_family_execution_routing_v2 = 844 manual_assignment
--   ml_ops invariato
--   ml_diag invariato (dipendenza critica di v_family_model_registry_v2)
-- =============================================================================

BEGIN;

-- STEP 1: Pre-check invarianti produzione
DO $$
DECLARE
    v_n_assign  INT;
    v_n_routing INT;
BEGIN
    SELECT COUNT(*) INTO v_n_assign  FROM ml_forecast.family_model_assignment_v1;
    SELECT COUNT(*) INTO v_n_routing FROM ml_forecast.v_family_execution_routing_v2
    WHERE routing_source = 'manual_assignment';

    IF v_n_assign <> 844 THEN
        RAISE EXCEPTION 'G ABORTED: assignment count = %, attesi 844', v_n_assign;
    END IF;
    IF v_n_routing <> 844 THEN
        RAISE EXCEPTION 'G ABORTED: routing count = %, attesi 844', v_n_routing;
    END IF;
    RAISE NOTICE 'PRE-CHECK OK: assignment=%, routing=%', v_n_assign, v_n_routing;
END;
$$;

-- STEP 2: Drop _bak_* tables (snapshot migration, 0 dipendenze, 1.72MB)
DROP TABLE IF EXISTS ml_forecast._bak_family_model_registry_v2_20260310;
DROP TABLE IF EXISTS ml_forecast._bak_family_model_registry_v2_20260312;
DROP TABLE IF EXISTS ml_forecast._bak_family_model_registry_v2_before_engine_20260310;
DROP TABLE IF EXISTS ml_forecast._bak_family_model_registry_v2_before_engine_routing_20260310;
DROP TABLE IF EXISTS ml_forecast._bak_family_model_registry_v2_before_state_hardening_20260310;
DROP TABLE IF EXISTS ml_forecast._bak_family_model_state_v1_20260310;
DROP TABLE IF EXISTS ml_forecast._bak_family_model_state_v1_20260312;
DROP TABLE IF EXISTS ml_forecast._bak_family_model_state_v1_before_state_hardening_20260310;
DROP TABLE IF EXISTS ml_forecast._bak_model_catalog_v1_20260313;
DROP TABLE IF EXISTS ml_forecast._bak_model_catalog_v1_c_20260313;
DROP TABLE IF EXISTS ml_forecast._bak_model_engine_map_v1_20260313;
DROP TABLE IF EXISTS ml_forecast._bak_model_engine_map_v1_before_naive_zero_test_20260311;
DROP TABLE IF EXISTS ml_forecast._bak_routing_v2_def_20260313;
DROP TABLE IF EXISTS ml_forecast._bak_suggestion_bm_c1_pre;
DROP TABLE IF EXISTS ml_forecast._bak_suggestion_bm_v1_c_20260313;

-- STEP 3: Drop tabella legacy vuota (0 righe, no deps, non usata da codice attivo)
DROP TABLE IF EXISTS ml_forecast.family_model_suggestion_classification_v1;

-- STEP 4: Marcare v_family_model_registry_v1 come deprecated
-- La tabella base (family_model_registry_v1) rimane intatta perché è il source di questa vista.
-- validate_engines.py usa v_family_execution_routing_v1, non questa vista.
COMMENT ON VIEW ml_forecast.v_family_model_registry_v1 IS
'[DEPRECATED — Blocco G] Usa family_model_registry_v1 (old table v1, 845 righe).
 Vista attiva è v_family_model_registry_v2 (basata su family_model_registry_v2 + ml_diag).
 Tenuta per compatibilità. Da eliminare dopo verifica nessun consumer esterno.';

-- STEP 5: Post-check
DO $$
DECLARE
    v_n_assign   INT;
    v_n_routing  INT;
    v_n_bak      INT;
    v_n_ops_runs INT;
BEGIN
    SELECT COUNT(*) INTO v_n_assign  FROM ml_forecast.family_model_assignment_v1;
    SELECT COUNT(*) INTO v_n_routing FROM ml_forecast.v_family_execution_routing_v2
    WHERE routing_source = 'manual_assignment';
    SELECT COUNT(*) INTO v_n_bak
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='ml_forecast' AND c.relname LIKE '_bak_%' AND c.relkind='r';
    SELECT COUNT(*) INTO v_n_ops_runs FROM ml_ops.pipeline_run_log_v1;

    IF v_n_assign  <> 844 THEN RAISE EXCEPTION 'POST-CHECK FAILED: assignment=%', v_n_assign; END IF;
    IF v_n_routing <> 844 THEN RAISE EXCEPTION 'POST-CHECK FAILED: routing=%', v_n_routing; END IF;
    IF v_n_bak     <>   0 THEN RAISE EXCEPTION 'POST-CHECK: rimangono % _bak_ tables', v_n_bak; END IF;

    RAISE NOTICE 'BLOCCO G MIGRATION OK';
    RAISE NOTICE '  _bak_* tables rimaste: %',       v_n_bak;
    RAISE NOTICE '  assignment: %',                  v_n_assign;
    RAISE NOTICE '  routing manual_assignment: %',   v_n_routing;
    RAISE NOTICE '  ml_ops.pipeline_run_log_v1: %',  v_n_ops_runs;
END;
$$;

COMMIT;
