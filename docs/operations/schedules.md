# Greenbrain Unified Schedule
> Single source of truth for all job scheduling: systemd timers + pg_cron.
> Evidence-based from unit files (`/etc/systemd/system/gh-*.timer`) and `cron.job` table on Supabase.
> Generated: 2026-03-27.

---

## Timezone convention

| Runtime | Timezone | Notes |
|---------|----------|-------|
| systemd timers | **System local** (server is UTC+1 winter / UTC+2 summer — Europe/Rome) | `OnCalendar=` expressions use local time |
| pg_cron | **UTC** | Supabase default; no `cron.job.timezone` override confirmed |

**Offset at time of writing:** UTC+1. Approx UTC column below uses UTC+1 offset. Adjust +1h in summer.

---

## Unified Schedule Table

Sorted by approximate UTC fire time (daily cycle). Windowed jobs show window start.

| Job | Runtime | Schedule | TZ | Approx UTC | Gate / Precheck | Upstream | Downstream | Status | Notes |
|-----|---------|----------|----|------------|-----------------|----------|------------|--------|-------|
| `ops_pipeline_monitor_snapshot` (#28) | pg_cron | `*/15 * * * *` | UTC | continuous | none | — | `v_ops_pipeline_monitor_latest`, FastAPI `/ops` | ✅ canonical | Low-cost snapshot every 15 min |
| `run_greenhouse_daily_pipeline_full` (#30) | pg_cron | `* * * * *` | UTC | continuous | none | — | same as #11 | ⛔ **DISABLE** | Duplicate of #39; no gate; runs 1440×/day |
| `ops_maybe_run_daily_pipeline` (#38) | pg_cron | `* * * * *` | UTC | continuous | internal: checks `etl.t_etl_runs` | — | same as #29 | ⛔ **DISABLE** | Excessive; 1440×/day. Covered by #29 + #37 |
| `run_greenhouse_daily_pipeline_full` (#39) | pg_cron | `* * * * *` | UTC | continuous | none | — | same as #11 | ⛔ **DISABLE** | Duplicate of #30; no gate; runs 1440×/day |
| `core_planner__nightly_roll4_reset` (#12) | pg_cron | `5 1 * * *` | UTC | 01:05 | none | — | `t_core_planner__orchestrator_state`; pg_cron #13 | ✅ canonical | Must complete before #13 at 12:00 |
| `ops_refresh_pipeline_monitor_snapshot` (#34) | pg_cron | `*/30 0-9,13-23 * * *` | UTC | 00:00–09:00, 13:00–23:00 | none | `t_ops_pipeline_monitor` | `mv_core_analytics__*`, `mv_famiglie_catalog` | ✅ canonical | Off-hours low-cadence MV refresh |
| `ops_maybe_run_daily_pipeline` (#37) | pg_cron | `*/5 9-11 * * *` | UTC | 09:00–11:55 | internal: checks `etl.t_etl_runs` | raw data tables | `greenhouse_forecast_features_dense`, analytics tables | ✅ canonical | Early morning gated catch-up before job #11 window |
| `ops_refresh_pipeline_monitor_snapshot` (#35) | pg_cron | `*/5 9-11 * * *` | UTC | 09:00–11:55 | none | pipeline tables | `mv_core_analytics__*` | ✅ canonical | Fine-cadence MV refresh, same window as #37 |
| `run_greenhouse_daily_pipeline_full` (#11) | pg_cron | `*/5 10-11 * * *` | UTC | 10:00–11:55 | none (ungated) | `greenhouse_sales_raw`, raw tables | `greenhouse_forecast_features_dense`, `t_core_analytics__*`, `t_dashboard_sales_*`, `etl.t_etl_runs` | ✅ canonical | Primary production ETL trigger |
| `ops_refresh_pipeline_monitor_snapshot` (#32) | pg_cron | `*/2 10-12 * * *` | UTC | 10:00–12:00 | none | pipeline tables | `mv_core_analytics__*` | ✅ canonical | High-cadence MV refresh during ETL window |
| `core_planner__nightly_roll4_tick` (#13) | pg_cron | `0 12 * * *` | UTC | 12:00 | none (reads whatever forecast is current) | `greenhouse_forecast_results_v2`, `famiglie_catalog_static`, planner params | `t_core_planner__fact_weekly`, `heat_cells`, `assortment_calendar`, `density` | ✅ canonical | Reads predict output from 00:30 UTC run (01:30 local). Late predict → stale planner. |
| `ops_maybe_run_daily_pipeline` (#29) | pg_cron | `*/5 19-23 * * *` | UTC | 19:00–23:55 | internal: checks `etl.t_etl_runs` | raw data tables | `greenhouse_forecast_features_dense`, analytics tables | ✅ canonical | Evening catch-up gate for late data |
| `ops_refresh_pipeline_monitor_snapshot` (#31) | pg_cron | `*/10 19-23 * * *` | UTC | 19:00–23:55 | none | pipeline tables | `mv_core_analytics__*` | ✅ canonical | MV refresh during evening ETL window |
| `gh-parquet-export` | systemd | `OnCalendar=*-*-* 21:35:00` ±2min | local | **≈20:35 UTC** | `check_etl_ready.sh` → `etl.t_etl_runs` must have `status=success` today | `greenhouse_forecast_features_dense` | Supabase Storage parquet; `ops_parquet_export_runs/state` | 🟡 partial migration | Blocks if ETL not succeeded. Script hardcodes `/opt/greenhouse/repo` path. |
| `gh-refresh-registry` | systemd | `OnCalendar=*-*-* 00:45:00` ±3min | local | **≈23:45 UTC** | none | `ml_forecast.v_family_execution_routing_v2`, `ml_diag` source tables | `family_model_registry_v1/v2`; 9 `ml_diag.mv_*` refreshed | ✅ migrated | Only systemd job running Python from monorepo |
| `gh-train-missing` | systemd | `OnCalendar=*-*-* 01:10:00` ±2min | local | **≈00:10 UTC** | none | `ml_forecast.v_train_missing_candidates_v1`; parquet; DO Spaces bundles | DO Spaces model bundles; `family_model_state_v1`; `family_run_log_v1` | 🟡 partial migration | Post: `gh-sync-local-artifacts`. Lock: `/opt/greenhouse/tmp/train_missing.lock` |
| `gh-predict-all` | systemd | `OnCalendar=*-*-* 01:30:00` ±2min | local | **≈00:30 UTC** | none (lock file check in Python) | `family_model_registry_v1/v2`; parquet; DO Spaces bundles; priors | `greenhouse_forecast_results_v2`; `t_forecast_fam_daily`; `ml_ops` logs | 🟡 partial migration | **Critical output job.** Lock: `/opt/greenhouse/tmp/predict_all.lock` |
| `gh-train-biweekly-all` | systemd | `OnCalendar=Sun *-*-01,15 02:00:00` ±5min | local | **≈01:00 UTC** (biweekly) | none | `ml_forecast.v_family_execution_routing_v2`; parquet; DO Spaces | DO Spaces bundles; `family_model_state_v1` | 🔴 not migrated | Fires only on Sundays that are 1st or 15th. `EnvironmentFile=/opt/greenhouse/.env` |
| `gh-train-quarterly` | systemd | `OnCalendar=*-01,04,07,10-01 02:30:00` ±15min | local | **≈01:30 UTC** (quarterly) | none | Same as biweekly | Same as biweekly | 🔴 not migrated | Fires on Jan 1, Apr 1, Jul 1, Oct 1 regardless of weekday. Captures `GIT_SHA`. |

---

## Conflicts and Anomalies

### ⛔ Critical: Every-minute ETL jobs (jobs 30, 38, 39)

```
pg_cron #30  * * * * *  run_greenhouse_daily_pipeline_full(40,14,2)   ← DISABLE
pg_cron #38  * * * * *  ops_maybe_run_daily_pipeline()                ← DISABLE
pg_cron #39  * * * * *  run_greenhouse_daily_pipeline_full(40,14,2)   ← DISABLE
```

**During 10:00–11:55 UTC**, jobs 11, 30, and 39 all call `run_greenhouse_daily_pipeline_full` at
overlapping intervals. At worst: 2 invocations/minute from #30+#39, plus 1 invocation/5min from #11
= up to **3 concurrent full ETL invocations per minute**.

Job #38 calls `ops_maybe_run_daily_pipeline` every minute (1440×/day vs 240×/day for #29+#37).
Even if the internal guard prevents double-writes, the function is still called and costs DB connections.

**Fix:**
```sql
SELECT cron.unschedule(30);
SELECT cron.unschedule(38);
SELECT cron.unschedule(39);
```

---

### ⚠️ Schedule overlap: #37 vs #35 (same window, same time slot)

```
pg_cron #37  */5 9-11 * * *  ops_maybe_run_daily_pipeline()               ← keep
pg_cron #35  */5 9-11 * * *  ops_refresh_pipeline_monitor_snapshot()       ← keep
```

Same schedule string, different functions. **Not a conflict** — they are independent operations.
Both fire at the same times but do unrelated things.

---

### ⚠️ Systemd timing dependency chain (tight margins)

```
00:45 local  gh-refresh-registry  (duration: ~3–8 min)
01:10 local  gh-train-missing     (duration: 0 min to several hours)
01:30 local  gh-predict-all       (duration: ~30–90 min)
```

Margins:
- **25 min** between refresh-registry start and train-missing start — adequate.
- **20 min** between train-missing start and predict-all start — **potentially tight** if train-missing runs long (many missing families). systemd does not enforce ordering; predict-all starts regardless of whether train-missing is still running.
- Both services use lock files (`train_missing.lock`, `predict_all.lock`) which prevent duplicate runs of the same job, but **do not prevent predict-all from starting while train-missing is in progress**.

---

### ⚠️ Planner tick reads stale forecast if predict-all runs late

```
01:30 local  gh-predict-all  → writes greenhouse_forecast_results_v2
12:00 UTC    pg_cron #13     → reads  greenhouse_forecast_results_v2
```

If `gh-predict-all` takes longer than ~2h (unusual but possible during biweekly full retrain overlap),
the planner tick at 12:00 UTC (13:00 local) reads yesterday's forecast results.
No hard dependency or wait mechanism exists between these two.

---

### ⚠️ gh-parquet-export gate: single point of failure

```
21:35 local  gh-parquet-export
  ExecStartPre: check_etl_ready.sh
    → SELECT status FROM etl.t_etl_runs WHERE run_date = today AND status = 'success'
    → exits 1 if not found → systemd marks service as FAILED (ExecStartPre failure)
```

If ETL has not succeeded by 21:35 local time on any given day (including weekends, holidays),
parquet export is skipped entirely for that day. `Persistent=true` means it will attempt to catch up
on next boot, but **not** on next timer fire (timers only catch up missed runs since last boot, not
missed calendar slots while running).

---

### ℹ️ gh-train-biweekly-all: schedule fires less often than expected

```
OnCalendar=Sun *-*-01,15 02:00:00
```

Fires only when **both conditions are true**: day is Sunday AND day-of-month is 1 or 15.
Most months the 1st and 15th are not Sundays. Approximate real frequency: **every 6–8 weeks**.
This is likely intentional (avoid competing with other Sun night jobs) but should be confirmed.

---

## Execution Timeline

Full daily pipeline: raw data → ETL → parquet → registry → train → predict → analytics → planner.

### Normal day (all systems nominal)

```
────────────────── UTC ──────────────────────────────────────────────────────────────
 09:00  pg_cron #37  ops_maybe_run_daily_pipeline()  [gated: skip if already ran]
        pg_cron #35  ops_refresh_pipeline_monitor_snapshot()  [MV refresh]

 10:00  pg_cron #11  run_greenhouse_daily_pipeline_full(40, 14, 2)  [every 5min]
        pg_cron #32  ops_refresh_pipeline_monitor_snapshot()  [every 2min]
            │
            │  ETL PROCESSING (typically completes within first 1–2 runs)
            │  → refresh_dense_range()
            │  → refresh_forecast_features_dense_range()
            │  → refresh_core_analytics_range()
            │  → refresh_dashboard_sales_range()
            │  writes: etl.t_etl_runs {status: success, run_date: today}
            │  writes: greenhouse_forecast_features_dense
            │          t_core_analytics__* (48+ tables)
            │          t_dashboard_sales_* (4 tables)
            │
────────────────── local (UTC+1) ────────────────────────────────────────────────────

 20:35 (≈) gh-parquet-export  [systemd, 21:35 local ±2min]
            ExecStartPre: check_etl_ready.sh
              ├─ ✅ ETL succeeded today → proceed
              └─ ❌ ETL not found → service FAILS, parquet skipped for today
            run_daily_parquet_batches.sh (17 batches × 50 families)
              → export_features_dense.py reads greenhouse_forecast_features_dense
              → writes Supabase Storage: ml-snapshots/features_dense/v1/year=Y/slug=S/part.parquet
              → writes ops_parquet_export_runs, ops_parquet_export_state

 23:45 (≈) gh-refresh-registry  [systemd, 00:45 local ±3min]
            ExecStartPre: gh-refresh-ml-diag
              → REFRESH CONCURRENTLY 9 ml_diag.mv_*  (~3–8 min)
            gh-refresh-registry
              → python3 -m jobs.refresh_registry
              → reads  ml_forecast.v_family_execution_routing_v2
              → writes ml_forecast.family_model_registry_v1  (train candidates)
              → writes ml_forecast.family_model_registry_v2  (predict candidates)

────────────────── UTC (next calendar day) ──────────────────────────────────────────

 00:05  pg_cron #12  core_planner__nightly_roll4_reset()
          → resets t_core_planner__orchestrator_state, refresh_state

 00:10 (≈) gh-train-missing  [systemd, 01:10 local ±2min]
            run_train_missing.sh
              → python3 -m jobs.train_missing_batches
              → reads  ml_forecast.v_train_missing_candidates_v1
              → for each missing family:
                  ensure_model_bundle.py (check/download DO Spaces)
                  train_v4_single_family_tweedie.py
                    reads:  Supabase Storage parquet OR DB fallback
                    writes: DO Spaces models_v4/bundle_<slug>_v4.pkl
                    writes: family_model_state_v1, model_artifact_registry_v1
                    writes: ml_ops.family_run_log_v1
            ExecStartPost: gh-sync-local-artifacts

 00:30 (≈) gh-predict-all  [systemd, 01:30 local ±2min]
            run_predict_all.sh
              → build_seasonal_priors.py
                    reads:  famiglie_catalog_static
                    writes: priors_cache/priors_v1.parquet (local)
              → upload_priors_to_supabase
                    writes: Supabase Storage priors/priors_v1.parquet
              → download_priors_from_supabase
                    reads:  Supabase Storage priors/priors_v1.parquet
              → python3 -m jobs.predict_all
                    reads:  famiglie_catalog_static
                    reads:  family_model_registry_v1/v2
                    for each family:
                      ensure_model_bundle.py (download from DO Spaces)
                      predict_v4_single_family_tweedie.py
                        reads:  Supabase Storage parquet OR DB fallback
                        reads:  priors_cache/priors_v1.parquet
                        reads:  models_v4/<slug>/bundle_<slug>_v4.pkl (DO Spaces)
                        writes: greenhouse_forecast_results_v2  ← PRIMARY OUTPUT
                        writes: t_forecast_fam_daily
                        writes: ml_ops.family_run_log_v1, pipeline_run_log_v1

 11:00  pg_cron #13  core_planner__nightly_roll4_tick(2)  [12:00 UTC]
          → reads  greenhouse_forecast_results_v2  (from 00:30 UTC predict run)
          → reads  greenhouse_forecast_features_dense
          → reads  famiglie_catalog_static, planner params
          → writes t_core_planner__fact_weekly
          → writes t_core_planner__heat_cells
          → writes t_core_planner__assortment_calendar
          → writes t_core_planner__density
          ← Frontend Planner page reflects updated data from ~12:00 UTC (13:00 local)

────────────────── Background (all day) ─────────────────────────────────────────────

 */15  pg_cron #28  ops_pipeline_monitor_snapshot()
          → appends to t_ops_pipeline_monitor
          ← FastAPI /api/v1/ops reads latest snapshot via v_ops_pipeline_monitor_latest

 MV refresh jobs (pipeline monitoring views):
   09:00–11:55  #35: */5 min
   09:00–11:55  #37: */5 min (gated ETL — usually skips if #11 already ran)
   10:00–12:00  #32: */2 min
   19:00–23:55  #29: */5 min (gated ETL — evening catch-up)
   19:00–23:55  #31: */10 min
   off-hours    #34: */30 min

────────────────── Periodic (non-daily) ─────────────────────────────────────────────

 Sun 1st+15th 01:00 UTC (≈)  gh-train-biweekly-all  [02:00 local ±5min]
   → train_all_monitor.py (ALL families, unconditional)
   → same train flow as train-missing but for every family
   → ExecStartPost: gh-sync-local-artifacts
   Effective frequency: ~every 6–8 weeks (fires only when 1st/15th is a Sunday)

 Jan/Apr/Jul/Oct 1st 01:30 UTC (≈)  gh-train-quarterly  [02:30 local ±15min]
   → same as biweekly but fires on 1st of Jan, Apr, Jul, Oct regardless of weekday
   → additionally captures GIT_SHA at runtime
```

---

### Failure modes and cascade effects

| Failure | Immediate effect | Cascade |
|---------|-----------------|---------|
| ETL fails (jobs 11/37 don't produce `etl.t_etl_runs` success) | `check_etl_ready.sh` exits 1 → `gh-parquet-export` fails | No fresh parquet → train/predict use stale data |
| `gh-parquet-export` fails | Parquet for today not written | Train/predict fall back to DB. Slower + more DB load. |
| `gh-refresh-registry` fails | Registry not updated | Train/predict use yesterday's candidate lists. Stale families skipped or re-run unnecessarily. |
| `gh-train-missing` fails | Some families have no model bundle | `predict-all` either skips them or triggers inline training via `AUTO_TRAIN_MISSING=1`. |
| `gh-predict-all` fails | No new forecast for today | Planner tick at 12:00 UTC reads yesterday's results. Frontend shows stale forecast. |
| pg_cron #12 fails | Planner state not reset | pg_cron #13 tick operates on stale orchestrator state → planner output may be inconsistent |

---

## Quick-disable commands (pg_cron)

Run these on the Supabase Postgres instance to remove the dangerous every-minute jobs:

```sql
-- Verify first:
SELECT jobid, schedule, command FROM cron.job WHERE jobid IN (30, 38, 39);

-- Disable:
SELECT cron.unschedule(30);
SELECT cron.unschedule(38);
SELECT cron.unschedule(39);
```

---

## Related documents

| Document | Path |
|----------|------|
| Job catalog (full per-job detail) | `docs/operations/job-catalog.md` |
| Full system inventory part 1 (entrypoints, scheduling) | `docs/operations/00-full-system-inventory-01.md` |
| Full system inventory part 3 (migration status, action plan) | `docs/operations/00-full-system-inventory-03.md` |
| Storage migration analysis | `docs/migration/04-storage-migration-analysis.md` |
