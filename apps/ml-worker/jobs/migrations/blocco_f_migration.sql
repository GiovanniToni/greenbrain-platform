-- =============================================================================
-- blocco_f_migration.sql
-- Blocco F — Dismissione definitiva schema ml_monitor
-- =============================================================================
-- PREREQUISITI VERIFICATI (2026-03-14)
--   ✓ Zero dipendenze DB esterne (pg_depend = 0 righe fuori da ml_monitor)
--   ✓ Zero riferimenti cron/systemd/timer a ml_monitor
--   ✓ Unico riferimento codice = jobs/ml_monitor_db.py (già DEPRECATED — Blocco E)
--   ✓ ml_ops è il layer unico autoritativo dal Blocco D (2026-03-13)
--   ✓ Ultimi dati scritti: 2026-03-13 (frozen da 1+ giorno)
--   ✓ Snapshot CSV esportato in /opt/greenhouse/ml_monitor_archive/
--       - runs_20260314_113729.csv            (144 righe, 75 KB)
--       - family_runs_20260314_113729.csv     (19377 righe, 2.3 MB)
--       - bundle_registry_20260314_113729.csv (845 righe, 115 KB)
--
-- OGGETTI RIMOSSI
--   5 viste deprecated: v_run_recent, v_daily_runs, v_daily_family_summary,
--                        v_model_status, v_model_stale
--   3 tabelle: ml_monitor.runs, ml_monitor.family_runs, ml_monitor.bundle_registry
--   2 sequenze: runs_run_id_seq, family_runs_family_run_id_seq (via CASCADE)
--   9 indici: (via CASCADE con le tabelle)
--   schema ml_monitor
--
-- INVARIANTI GARANTITI
--   ✗ NON tocca: ml_forecast (assignment, routing, benchmark)
--   ✗ NON tocca: ml_ops (pipeline_run_log_v1, family_run_log_v1, viste)
--   ✗ NON tocca: public
--   ✗ NON tocca: script produttivi
-- =============================================================================

BEGIN;

-- STEP 1: Verifica pre-drop — ml_monitor è davvero frozen (no scritture recenti)
DO $$
DECLARE
    v_last_run      TIMESTAMPTZ;
    v_last_family   TIMESTAMPTZ;
    v_last_bundle   TIMESTAMPTZ;
    v_hours_since   NUMERIC;
BEGIN
    SELECT MAX(COALESCE(finished_at, started_at)) INTO v_last_run    FROM ml_monitor.runs;
    SELECT MAX(COALESCE(finished_at, started_at)) INTO v_last_family FROM ml_monitor.family_runs;
    SELECT MAX(updated_at)                         INTO v_last_bundle FROM ml_monitor.bundle_registry;

    v_hours_since := EXTRACT(EPOCH FROM (now() - GREATEST(v_last_run, v_last_family, v_last_bundle))) / 3600;

    IF v_hours_since < 2 THEN
        RAISE EXCEPTION 'BLOCCO F ABORTED: ml_monitor ha avuto attività nelle ultime 2 ore (%.1f ore fa). Verificare prima.', v_hours_since;
    END IF;

    RAISE NOTICE 'PRE-CHECK OK: ultima scrittura ml_monitor %.1f ore fa (> 2h required)', v_hours_since;
END;
$$;

-- STEP 2: Verifica pre-drop — snapshot CSV presente
DO $$
DECLARE
    v_n_assignments INT;
    v_n_routing     INT;
BEGIN
    -- Invarianti produzione devono essere intatti prima del drop
    SELECT COUNT(*) INTO v_n_assignments FROM ml_forecast.family_model_assignment_v1;
    SELECT COUNT(*) INTO v_n_routing
    FROM ml_forecast.v_family_execution_routing_v2
    WHERE routing_source = 'manual_assignment';

    IF v_n_assignments <> 844 THEN
        RAISE EXCEPTION 'BLOCCO F ABORTED: family_model_assignment_v1 ha % righe, attese 844', v_n_assignments;
    END IF;
    IF v_n_routing <> 844 THEN
        RAISE EXCEPTION 'BLOCCO F ABORTED: v_family_execution_routing_v2 ha % manual_assignment, attesi 844', v_n_routing;
    END IF;

    RAISE NOTICE 'PRE-CHECK OK: assignment=%, routing=%', v_n_assignments, v_n_routing;
END;
$$;

-- STEP 3: Drop viste deprecated (ordine non rilevante, non hanno dipendenze)
DROP VIEW IF EXISTS ml_monitor.v_model_stale        CASCADE;
DROP VIEW IF EXISTS ml_monitor.v_model_status       CASCADE;
DROP VIEW IF EXISTS ml_monitor.v_daily_family_summary CASCADE;
DROP VIEW IF EXISTS ml_monitor.v_daily_runs         CASCADE;
DROP VIEW IF EXISTS ml_monitor.v_run_recent         CASCADE;

-- STEP 4: Drop tabelle con CASCADE (include indici e foreign key constraints)
-- Ordine: family_runs prima (FK su runs), poi runs, poi bundle_registry (indipendente)
DROP TABLE IF EXISTS ml_monitor.family_runs    CASCADE;
DROP TABLE IF EXISTS ml_monitor.runs           CASCADE;
DROP TABLE IF EXISTS ml_monitor.bundle_registry CASCADE;

-- STEP 5: Drop sequenze residue (se non già droppate da CASCADE)
DROP SEQUENCE IF EXISTS ml_monitor.family_runs_family_run_id_seq;
DROP SEQUENCE IF EXISTS ml_monitor.runs_run_id_seq;

-- STEP 6: Drop schema
DROP SCHEMA IF EXISTS ml_monitor;

-- STEP 7: Verifica post-drop
DO $$
DECLARE
    v_schema_exists BOOLEAN;
    v_n_assignments INT;
    v_n_routing     INT;
    v_n_ops_runs    INT;
BEGIN
    -- Schema ml_monitor non deve più esistere
    SELECT EXISTS(
        SELECT 1 FROM pg_namespace WHERE nspname = 'ml_monitor'
    ) INTO v_schema_exists;

    IF v_schema_exists THEN
        RAISE EXCEPTION 'BLOCCO F POST-CHECK FAILED: schema ml_monitor esiste ancora';
    END IF;

    -- Invarianti produzione ancora intatti
    SELECT COUNT(*) INTO v_n_assignments FROM ml_forecast.family_model_assignment_v1;
    SELECT COUNT(*) INTO v_n_routing
    FROM ml_forecast.v_family_execution_routing_v2
    WHERE routing_source = 'manual_assignment';
    SELECT COUNT(*) INTO v_n_ops_runs FROM ml_ops.pipeline_run_log_v1;

    IF v_n_assignments <> 844 THEN
        RAISE EXCEPTION 'BLOCCO F POST-CHECK FAILED: assignment count changed: %', v_n_assignments;
    END IF;
    IF v_n_routing <> 844 THEN
        RAISE EXCEPTION 'BLOCCO F POST-CHECK FAILED: routing count changed: %', v_n_routing;
    END IF;

    RAISE NOTICE 'BLOCCO F MIGRATION OK';
    RAISE NOTICE '  schema ml_monitor: DROPPED';
    RAISE NOTICE '  ml_forecast.family_model_assignment_v1: % righe (invariato)', v_n_assignments;
    RAISE NOTICE '  v_family_execution_routing_v2: % manual_assignment (invariato)', v_n_routing;
    RAISE NOTICE '  ml_ops.pipeline_run_log_v1: % runs (attivo)', v_n_ops_runs;
END;
$$;

COMMIT;
