# Greenbrain Job Catalog
> Canonical operational reference. Evidence-based from systemd unit files, pg_cron table, and Python source.
> Generated: 2026-03-27.

---

## Contents

- [Systemd Jobs](#systemd-jobs) — 6 services, all timer-driven
- [pg_cron Jobs](#pg_cron-jobs) — 13 jobs on Supabase PostgreSQL
  - [ETL Pipeline Triggers](#group-etl-pipeline-triggers) — jobs 11, 29, 37, 30⚠️, 38⚠️, 39⚠️
  - [Planner](#group-planner) — jobs 12, 13
  - [Monitor Snapshots](#group-monitor-snapshots) — jobs 28, 31, 32, 34, 35

---

## Systemd Jobs

### Daily execution order

```
21:35  gh-parquet-export      export features_dense → Supabase Storage parquet
00:45  gh-refresh-registry    refresh ml_diag MVs + family_model_registry
01:10  gh-train-missing       train families missing model bundles
01:30  gh-predict-all         build priors → predict all → write forecast results
Sun 1st+15th 02:00  gh-train-biweekly-all   full retrain all families
Jan/Apr/Jul/Oct 1st 02:30  gh-train-quarterly  full retrain all families
```

---

### Job: gh-parquet-export

- **Runtime:** systemd
- **Purpose:** Export `greenhouse_forecast_features_dense` to Supabase Storage as partitioned parquet files, consumed by ML training and prediction.
- **Code location:**
  - Pre-check: `/opt/greenbrain-platform/apps/ml-worker/jobs/parquet_export/check_etl_ready.sh`
  - Entry script: `/opt/greenbrain-platform/apps/ml-worker/jobs/parquet_export/scripts/run_daily_parquet_batches.sh`
  - Python: `/opt/greenhouse/repo/jobs/parquet_export/export_features_dense.py` ← (hardcoded `PROJECT_DIR` in script, not monorepo copy)
- **Invocation:**
  ```
  ExecStartPre: bash jobs/parquet_export/check_etl_ready.sh
  ExecStart:    bash jobs/parquet_export/scripts/run_daily_parquet_batches.sh
                  → cd /opt/greenhouse/repo/jobs/parquet_export
                  → for offset in 0 50 100 ... 800:
                      python -u export_features_dense.py --batch-offset $offset
  ```
- **Scheduler:**
  - Schedule: `OnCalendar=*-*-* 21:35:00`
  - Timezone: system local (UTC+1/Europe)
  - Persistent: yes · RandomizedDelaySec: 120s
- **Trigger mode:** timer-only (no manual invocation in bin scripts)
- **Inputs:**
  - Tables: `public.greenhouse_forecast_features_dense` (read in 17 batches of 50 families)
  - Tables: `etl.t_etl_runs` (pre-check: today's ETL must have `status=success` before job runs)
  - Env: `APP_ENV=dev`
- **Outputs:**
  - Storage: `ml-snapshots/features_dense/v1/year={Y}/famiglia_slug={slug}/part.parquet` (Supabase Storage bucket)
  - Tables: `public.ops_parquet_export_runs` (per-batch run record)
  - Tables: `public.ops_parquet_export_state` (last success date, read by check_etl_ready.sh for the next run)
- **Upstream dependencies:** ETL pipeline must complete (`etl.t_etl_runs success` for today). Triggered by pg_cron job 11.
- **Downstream consumers:** `gh-train-missing`, `gh-predict-all`, `gh-train-biweekly-all`, `gh-train-quarterly` — all read parquet from Supabase Storage via `data_access_v1.py`.
- **Env dependencies:**
  ```
  SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_BUCKET=ml-snapshots
  SUPABASE_DB_HOST, SUPABASE_DB_PORT, SUPABASE_DB_NAME, SUPABASE_DB_USER, SUPABASE_DB_PASSWORD
  (Note: uses SUPABASE_DB_* alias, not PG_* — divergence from all other ML jobs)
  DATABASE_URL (used by check_etl_ready.sh psql call)
  ```
- **Storage dependencies:** Supabase Storage (write), Supabase PostgreSQL (read)
- **Source of truth:** `/opt/greenhouse/repo/jobs/parquet_export/export_features_dense.py` ← **legacy path** (monorepo `.bak_phase2b` copy not running)
- **Migration status:** 🟡 Partial — entry script in monorepo; Python still runs from legacy. Storage abstraction migration in progress (`.bak_phase2b`). Env var naming divergence not fixed.
- **Risk:** 🔴 HIGH — env naming divergence (`SUPABASE_DB_*` vs `PG_*`) will cause startup crash on client deployment. `run_daily_parquet_batches.sh` hardcodes legacy Python path, blocking full monorepo migration.
- **Notes:** Runs 17 batch iterations (offset 0, 50, 100...800). Each batch processes up to 50 families for all years. Requires ETL to succeed same day; if ETL fails, parquet is not updated and ML training uses stale data next day.

---

### Job: gh-refresh-registry

- **Runtime:** systemd
- **Purpose:** Refresh 9 `ml_diag` materialized views then rebuild `family_model_registry_v1/v2`, which gates which families run in training and prediction.
- **Code location:**
  - Pre-step: `/opt/greenbrain-platform/infra/scripts/bin/gh-refresh-ml-diag`
  - Entry script: `/opt/greenbrain-platform/infra/scripts/bin/gh-refresh-registry`
  - Python: `/opt/greenbrain-platform/apps/ml-worker/jobs/refresh_registry.py` ← **monorepo** (only ML job running from monorepo)
- **Invocation:**
  ```
  ExecStartPre: source load_env.sh && gh-refresh-ml-diag
                  → psql: REFRESH MATERIALIZED VIEW CONCURRENTLY ml_diag.mv_* (9 views)
  ExecStart:    gh-refresh-registry
                  → source /opt/greenhouse/venv/bin/activate
                  → cd /opt/greenbrain-platform/apps/ml-worker
                  → python3 -u -m jobs.refresh_registry
  ```
- **Scheduler:**
  - Schedule: `OnCalendar=*-*-* 00:45:00`
  - Timezone: system local
  - Persistent: yes · RandomizedDelaySec: 180s
- **Trigger mode:** timer + manual (`gh-refresh-registry` CLI)
- **Inputs:**
  - Tables: `greenhouse_forecast_features_dense`, `greenhouse_sales_family_daily_dense`, and all upstream tables (for ml_diag MV refresh)
  - Tables: `ml_forecast.v_family_execution_routing_v2` (routing view for registry build)
  - Tables: `ml_forecast.family_model_state_v1` (current state)
- **Outputs:**
  - Tables: `ml_forecast.family_model_registry_v1` (training candidates)
  - Tables: `ml_forecast.family_model_registry_v2` (prediction candidates)
  - MVs: 9 `ml_diag.mv_*` refreshed (mv_family_day_base, mv_family_stats, mv_family_intermittency, mv_family_seasonality, mv_family_importance, mv_family_metrics_v3/v3b/v4/v5)
- **Upstream dependencies:** Should run after ETL + parquet export complete. Runs at 00:45 — ETL expected to finish same evening.
- **Downstream consumers:** `gh-train-missing` (reads `ml_forecast.v_train_missing_candidates_v1`), `gh-predict-all` (reads `family_model_registry_v1/v2`), `gh-train-biweekly-all`, `gh-train-quarterly`.
- **Env dependencies:**
  ```
  APP_ENV=dev (injected via Environment= in unit)
  RUN_TRIGGER_SOURCE=systemd_timer (injected via Environment= in unit)
  PG_HOST, PG_PORT, PG_DB, PG_USER, PG_PASSWORD, DATABASE_URL
  SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (loaded via load_env.sh → dev.env)
  ```
- **Storage dependencies:** Supabase PostgreSQL (read/write only — no object storage)
- **Source of truth:** `/opt/greenbrain-platform/apps/ml-worker/jobs/refresh_registry.py` ✅ monorepo is live
- **Migration status:** ✅ Migrated — only service fully running from monorepo Python
- **Risk:** 🟢 LOW
- **Notes:** The only systemd service where `WorkingDirectory`, shell script, and Python all align to the monorepo. `gh-refresh-ml-diag` (ExecStartPre) does 9 `REFRESH MATERIALIZED VIEW CONCURRENTLY` calls — can take several minutes on large data.

---

### Job: gh-train-missing

- **Runtime:** systemd
- **Purpose:** Identify families with missing model bundles (`v_train_missing_candidates_v1`) and train them. This ensures no family is skipped during predict.
- **Code location:**
  - Entry script: `/opt/greenbrain-platform/apps/ml-worker/jobs/run_train_missing.sh`
  - Python orchestrator: `/opt/greenhouse/repo/jobs/train_missing_batches.py`
  - Python engine: `/opt/greenhouse/repo/train_v4_single_family_tweedie.py` (subprocess)
  - Post-step: `/opt/greenhouse/repo/jobs/sync_local_artifacts.py`
- **Invocation:**
  ```
  ExecStart: bash jobs/run_train_missing.sh
               → cd /opt/greenhouse/repo
               → source /opt/greenhouse/venv/bin/activate
               → source /opt/greenbrain-platform/infra/scripts/load_env.sh
               → python -m jobs.train_missing_batches
                   → reads v_train_missing_candidates_v1
                   → for each missing family:
                       ensure_model_bundle.py (check/download from DO Spaces)
                       subprocess: python train_v4_single_family_tweedie.py <family>
  ExecStartPost: gh-sync-local-artifacts
               → python -m jobs.sync_local_artifacts
  ```
- **Scheduler:**
  - Schedule: `OnCalendar=*-*-* 01:10:00`
  - Timezone: system local
  - Persistent: yes · RandomizedDelaySec: 120s
- **Trigger mode:** timer + manual (`gh-train-missing` CLI)
- **Inputs:**
  - Tables: `ml_forecast.v_train_missing_candidates_v1` (which families need training)
  - Tables: `ml_forecast.family_model_registry_v1` (model state)
  - Storage: Supabase Storage `ml-snapshots/features_dense/v1/.../*.parquet` (feature data)
  - Storage: DO Spaces `models_v4/bundle_<slug>_v4.pkl` (existing bundles to check/download)
  - Files: `parquet_cache/` (local disk cache of downloaded parquet)
- **Outputs:**
  - Storage: DO Spaces `models_v4/bundle_<slug>_v4.pkl` (trained model bundles)
  - Tables: `ml_forecast.family_model_state_v1` (updated state per family)
  - Tables: `ml_forecast.model_artifact_registry_v1` (bundle registration)
  - Tables: `ml_ops.family_run_log_v1` (per-family run log)
  - Files: `models_v4/<slug>/` (local bundle files synced to DO Spaces by sync_local_artifacts)
- **Upstream dependencies:** `gh-refresh-registry` (must have run to populate `v_train_missing_candidates_v1`). Parquet export must be current for fresh training data.
- **Downstream consumers:** `gh-predict-all` (reads bundles trained here from DO Spaces)
- **Env dependencies:**
  ```
  PG_HOST, PG_PORT, PG_DB, PG_USER, PG_PASSWORD, PG_SSLMODE
  DATABASE_URL
  SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_BUCKET
  DO_SPACES_REGION, DO_SPACES_BUCKET, DO_SPACES_KEY, DO_SPACES_SECRET, SPACES_PREFIX
  PARQUET_ENABLE, PARQUET_FORCE, PARQUET_CACHE_DIR, PARQUET_DATASET_PREFIX
  TRAIN_BATCH_SIZE, TRAIN_LIMIT, TRAIN_TIMEOUT_SEC
  GH_BASE_DIR, GH_REPO_DIR, GH_LOG_DIR, GH_TMP_DIR
  ```
- **Storage dependencies:** DO Spaces (model bundles read/write), Supabase Storage (parquet read), local disk (parquet cache, model cache)
- **Source of truth:** `/opt/greenhouse/repo/jobs/train_missing_batches.py` ← legacy (run_train_missing.sh switches to legacy repo)
- **Migration status:** 🟡 Partial — entry script in monorepo; Python runs from legacy `/opt/greenhouse/repo`
- **Risk:** 🟠 HIGH — if any ML family fails training here, predict will skip or degrade that family. Parquet must be fresh; stale parquet causes stale models.
- **Notes:** `ExecStartPost=gh-sync-local-artifacts` uploads newly trained bundles from local disk to DO Spaces. Uses lock file at `/opt/greenhouse/tmp/train_missing.lock` to prevent concurrent runs. `TRAIN_BATCH_SIZE=10` by default.

---

### Job: gh-predict-all

- **Runtime:** systemd
- **Purpose:** Build seasonal priors, then run daily predictions for all families, writing results to `greenhouse_forecast_results_v2` which feeds the frontend and planner.
- **Code location:**
  - Entry script: `/opt/greenbrain-platform/apps/ml-worker/jobs/run_predict_all.sh`
  - Priors builder: `/opt/greenhouse/repo/tools/build_seasonal_priors.py`
  - Priors upload: `/opt/greenhouse/repo/jobs/upload_priors_to_supabase.py`
  - Priors download: `/opt/greenhouse/repo/jobs/download_priors_from_supabase.py`
  - Python orchestrator: `/opt/greenhouse/repo/jobs/predict_all.py`
  - Python engine: `/opt/greenhouse/repo/predict_v4_single_family_tweedie.py` (subprocess)
- **Invocation:**
  ```
  ExecStart: bash jobs/run_predict_all.sh
               → cd /opt/greenhouse/repo
               → source /opt/greenhouse/venv/bin/activate
               → source /opt/greenbrain-platform/infra/scripts/load_env.sh
               → psql → /tmp/slugs_all.txt (all family slugs from famiglie_catalog_static)
               → python -m tools.build_seasonal_priors --slugs-file /tmp/slugs_all.txt
               → python -m jobs.upload_priors_to_supabase
               → python -m jobs.download_priors_from_supabase
               → python -m jobs.predict_all
                   → reads family_model_registry_v1/v2
                   → for each family:
                       ensure_model_bundle.py (download from DO Spaces)
                       subprocess: python predict_v4_single_family_tweedie.py <family>
  ```
- **Scheduler:**
  - Schedule: `OnCalendar=*-*-* 01:30:00`
  - Timezone: system local
  - Persistent: yes · RandomizedDelaySec: 120s
- **Trigger mode:** timer + manual (`gh-predict-all` / `gh-predict-all-now` CLI)
- **Inputs:**
  - Tables: `public.famiglie_catalog_static` (all active families)
  - Tables: `ml_forecast.family_model_registry_v1` (train gating), `ml_forecast.family_model_registry_v2` (predict gating)
  - Storage: Supabase Storage `ml-snapshots/features_dense/v1/.../*.parquet` (feature data)
  - Storage: DO Spaces `models_v4/bundle_<slug>_v4.pkl` (per-family model bundle)
  - Files: `priors_cache/priors_v1.parquet` (seasonal priors — built and downloaded in same run)
  - Files: `parquet_cache/` (local disk cache)
- **Outputs:**
  - Tables: `public.greenhouse_forecast_results_v2` (primary forecast output — consumed by frontend + planner)
  - Tables: `public.t_forecast_fam_daily` (daily aggregate forecast)
  - Tables: `ml_ops.family_run_log_v1` (per-family execution log)
  - Tables: `ml_ops.pipeline_run_log_v1` (pipeline-level log)
  - Storage: Supabase Storage `priors/priors_v1.parquet` (uploaded, then downloaded back for consistency)
- **Upstream dependencies:** Requires `gh-refresh-registry` (registry must be fresh), `gh-train-missing` (model bundles must exist). Both run before 01:30.
- **Downstream consumers:** FastAPI `/api/v1/forecast` and `/api/v1/dashboard`, planner (pg_cron jobs 12/13), frontend (`greenhouse_forecast_results_v2`).
- **Env dependencies:**
  ```
  PG_HOST, PG_PORT, PG_DB, PG_USER, PG_PASSWORD, PG_SSLMODE
  DATABASE_URL
  SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_KEY (legacy alias), SUPABASE_BUCKET
  DO_SPACES_REGION, DO_SPACES_BUCKET, DO_SPACES_KEY, DO_SPACES_SECRET, SPACES_PREFIX
  PARQUET_ENABLE, PARQUET_FORCE, PARQUET_CACHE_DIR, PARQUET_DATASET_PREFIX
  PRIORS_LOCAL_PATH, PRIORS_REMOTE_PATH
  FAMIGLIE_SOURCE_TABLE, FAMIGLIE_COL
  PREDICT_LIMIT, PREDICT_ONLY_FAMILY, PREDICT_FAMILY_TIMEOUT_SEC
  AUTO_TRAIN_MISSING
  V4_PRIOR_SMOOTH_DOY, V4_ENABLE_DOY_GATE, V4_DOY_GATE_MODE, V4_DOY_SMOOTH, V4_DOY_SOFT_FLOOR
  V4_DOY_SOFT_MULT, V4_DOY_HARD_FLOOR, V4_DOY_GATE_DEBUG
  V4_ENABLE_HURDLE, V4_HURDLE_P_FLOOR, V4_HURDLE_P_CAP, V4_HURDLE_P_POWER, V4_HURDLE_DEBUG
  GH_BASE_DIR, GH_REPO_DIR, GH_LOG_DIR, GH_TMP_DIR
  RUN_TRIGGER_SOURCE
  ```
- **Storage dependencies:** DO Spaces (model bundles read), Supabase Storage (parquet read, priors read/write), local disk (parquet cache, priors cache, models cache)
- **Source of truth:** `/opt/greenhouse/repo/jobs/predict_all.py` ← legacy
- **Migration status:** 🟡 Partial — entry script in monorepo; all Python in legacy. Priors storage migration in progress (`.bak_phase2c`).
- **Risk:** 🔴 CRITICAL — this is the primary ML output job. Any failure means forecast data is stale for the next full day. Uses lock at `/opt/greenhouse/tmp/predict_all.lock`.
- **Notes:** `AUTO_TRAIN_MISSING=1` causes predict to trigger inline training if a bundle is missing (fallback). Lock file prevents concurrent runs. Uses `SUPABASE_KEY` (alias for `SUPABASE_SERVICE_ROLE_KEY`) in `data_access_v1.py` — both must be set.

---

### Job: gh-train-biweekly-all

- **Runtime:** systemd
- **Purpose:** Full retrain of ALL families on the 1st and 15th of each month (Sunday only). Refreshes all model bundles, not just missing ones. Handles slow seasonal/model drift.
- **Code location:**
  - Python orchestrator: `/opt/greenhouse/repo/jobs/train_all_monitor.py` (absolute path in unit)
  - Python engine: `/opt/greenhouse/repo/train_v4_single_family_tweedie.py` (subprocess)
  - Post-step: `/opt/greenhouse/bin/gh-sync-local-artifacts` ← **legacy bin**
- **Invocation:**
  ```
  ExecStart: source /opt/greenhouse/venv/bin/activate
             export RUN_TRIGGER_SOURCE=systemd_timer
             python3 -u jobs/train_all_monitor.py
               → reads ml_forecast.v_family_execution_routing_v2 (all families)
               → for each family:
                   subprocess: python train_v4_single_family_tweedie.py <family>
  ExecStartPost: /opt/greenhouse/bin/gh-sync-local-artifacts
  ```
- **Scheduler:**
  - Schedule: `OnCalendar=Sun *-*-01,15 02:00:00`
  - Timezone: system local
  - Persistent: yes · RandomizedDelaySec: 300s
- **Trigger mode:** timer + manual (`gh-train-biweekly-all` CLI)
- **Inputs:**
  - Tables: `ml_forecast.v_family_execution_routing_v2` (all active families)
  - Storage: Supabase Storage parquet (feature data), or DB fallback
  - Storage: DO Spaces existing model bundles (downloaded for incremental retrain)
- **Outputs:**
  - Storage: DO Spaces `models_v4/bundle_<slug>_v4.pkl` (all bundles refreshed)
  - Tables: `ml_forecast.family_model_state_v1`
  - Tables: `ml_ops.family_run_log_v1`
- **Upstream dependencies:** Parquet must be current. Registry view must exist.
- **Downstream consumers:** `gh-predict-all` next run reads refreshed bundles.
- **Env dependencies:** Loaded entirely from `EnvironmentFile=/opt/greenhouse/.env` (not `load_env.sh`). Same set as `gh-train-missing` minus `TRAIN_BATCH_SIZE/LIMIT`.
  ```
  PG_*, DATABASE_URL, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, DO_SPACES_*, PARQUET_*, GH_*
  TRAIN_ALL_JOBS (optional — controls parallel workers)
  RUN_TRIGGER_SOURCE=systemd_timer
  ```
- **Storage dependencies:** DO Spaces (model bundles), Supabase Storage (parquet)
- **Source of truth:** `/opt/greenhouse/repo/jobs/train_all_monitor.py` ← all legacy
- **Migration status:** 🔴 Not migrated — `WorkingDirectory=/opt/greenhouse/repo`, `EnvironmentFile=/opt/greenhouse/.env`, legacy bin in ExecStartPost
- **Risk:** 🟠 HIGH — runs at 02:00 which overlaps with `gh-train-missing` (01:10) if training is slow. `TimeoutStartSec=0` so it runs indefinitely. Biweekly schedule fires only on Sundays that are the 1st or 15th — if month 1st/15th is not a Sunday, no run.
- **Notes:** `TRAIN_ALL_JOBS` controls parallel subprocess workers. Different from `gh-train-missing` in that it trains ALL families unconditionally, not just missing ones.

---

### Job: gh-train-quarterly

- **Runtime:** systemd
- **Purpose:** Full force-retrain of ALL families on 1st Jan, Apr, Jul, Oct. Intended for quarterly model refresh and seasonal drift correction.
- **Code location:**
  - Python: `/opt/greenhouse/repo/jobs/train_all_monitor.py` (absolute path in ExecStart)
  - Post-step: `/opt/greenhouse/bin/gh-sync-local-artifacts` ← legacy bin
- **Invocation:**
  ```
  ExecStart: source /opt/greenhouse/venv/bin/activate
             export RUN_TRIGGER_SOURCE=systemd_timer
             export GIT_SHA=$(cd /opt/greenhouse/repo && git rev-parse --short HEAD)
             python3 -u /opt/greenhouse/repo/jobs/train_all_monitor.py
  ExecStartPost: /opt/greenhouse/bin/gh-sync-local-artifacts
  ```
- **Scheduler:**
  - Schedule: `OnCalendar=*-01,04,07,10-01 02:30:00`
  - Timezone: system local
  - Persistent: yes · RandomizedDelaySec: 900s
- **Trigger mode:** timer only (quarterly)
- **Inputs:** Same as `gh-train-biweekly-all`
- **Outputs:** Same as `gh-train-biweekly-all`. Additionally records `GIT_SHA` in `ml_ops.pipeline_run_log_v1`.
- **Upstream dependencies:** Same as `gh-train-biweekly-all`
- **Downstream consumers:** Same as `gh-train-biweekly-all`
- **Env dependencies:** `EnvironmentFile=/opt/greenhouse/.env` (same as biweekly). `GIT_SHA` captured at runtime.
- **Storage dependencies:** Same as `gh-train-biweekly-all`
- **Source of truth:** `/opt/greenhouse/repo/jobs/train_all_monitor.py` ← all legacy
- **Migration status:** 🔴 Not migrated
- **Risk:** 🟠 HIGH — same as biweekly. `TimeoutStartSec=0` — will run indefinitely. RandomizedDelaySec=900 (15min jitter).
- **Notes:** Functionally identical to `gh-train-biweekly-all` except for schedule and `GIT_SHA` capture. The two services could share a single service unit with different timer units.

---

## pg_cron Jobs

All jobs run on the **Supabase hosted PostgreSQL** instance (`aws-1-eu-west-1.pooler.supabase.com`).
Timezone: Supabase default (UTC unless schema overrides).

---

### Group: ETL Pipeline Triggers

These jobs call the daily ETL pipeline, which populates `greenhouse_forecast_features_dense` and all analytics tables.

---

#### Job: pg_cron #11 — run_greenhouse_daily_pipeline_full (morning window)

- **Runtime:** pg_cron
- **Purpose:** Run the full ETL pipeline during the morning data-availability window (10:00–11:55). This is the primary production ETL trigger.
- **Code location:** SQL function `public.run_greenhouse_daily_pipeline_full(horizon int, rebuild_days int, ver int)`
- **Invocation:** `SELECT run_greenhouse_daily_pipeline_full(40, 14, 2)`
- **Scheduler:**
  - Schedule: `*/5 10-11 * * *` (every 5 minutes, 10:00–11:55 UTC)
  - Has internal guard: writes to `etl.t_etl_runs`; repeated calls are idempotent if guard is inside function
- **Trigger mode:** pg_cron automatic
- **Inputs:**
  - Tables: `greenhouse_sales_raw`, `greenhouse_products_normalized`, `greenhouse_weather_daily`, `greenhouse_holidays`, `greenhouse_weekday_strength*`, `famiglie_catalog_static`, `dim_iso_day`
- **Outputs:**
  - Tables: `greenhouse_sales_family_daily_fact`, `greenhouse_sales_family_daily_dense`, `greenhouse_forecast_features_dense`
  - Tables: `t_core_analytics__*` (48+ analytics tables), `t_dashboard_sales_*` (4 tables)
  - Tables: `etl.t_etl_runs`, `etl.t_etl_steps` (run tracking)
- **Upstream dependencies:** Raw data tables must be populated by external gestionale ETL
- **Downstream consumers:** `check_etl_ready.sh` (reads `etl.t_etl_runs`), `gh-parquet-export` (runs at 21:35 after this), analytics API, dashboard API
- **Env dependencies:** None (runs inside Supabase PG)
- **Storage dependencies:** None
- **Source of truth:** Supabase PostgreSQL function
- **Migration status:** 🔴 Not in monorepo SQL — no versioned SQL file in `sql/cron/`
- **Risk:** 🟢 LOW — window-gated, every 5 minutes. Acceptable.
- **Notes:** Parameters: `horizon=40` (days), `rebuild_days=14`, `ver=2`. Runs at most 24 times (2 hours × 12 per hour). See jobs 30 and 39 for critical duplicates.

---

#### Job: pg_cron #29 — ops_maybe_run_daily_pipeline (evening window)

- **Runtime:** pg_cron
- **Purpose:** Gated retry of ETL pipeline in the evening window (19:00–23:55). Runs only if today's pipeline has not yet succeeded (`ops_maybe_run_daily_pipeline` checks `etl.t_etl_runs` internally).
- **Code location:** SQL function `public.ops_maybe_run_daily_pipeline()`
- **Invocation:** `SELECT ops_maybe_run_daily_pipeline()`
- **Scheduler:**
  - Schedule: `*/5 19-23 * * *` (every 5 minutes, 19:00–23:55 UTC)
- **Trigger mode:** pg_cron automatic
- **Inputs:** Same raw data tables as job 11. Reads `etl.t_etl_runs` to check if already succeeded.
- **Outputs:** Same as job 11 (only if pipeline has not yet run today)
- **Upstream dependencies:** None
- **Downstream consumers:** Same as job 11
- **Env dependencies:** None
- **Storage dependencies:** None
- **Source of truth:** Supabase PostgreSQL function
- **Migration status:** 🔴 Not in monorepo SQL
- **Risk:** 🟢 LOW — gated by internal check, window-restricted
- **Notes:** Provides a safety net for late data availability. If raw data arrives after 12:00, this catches it.

---

#### Job: pg_cron #37 — ops_maybe_run_daily_pipeline (morning gate)

- **Runtime:** pg_cron
- **Purpose:** Gated ETL trigger in the morning window (09:00–11:55), before the raw `*/5 10-11` window of job 11. Allows early runs if data is ready at 09:00.
- **Code location:** Same as job 29: `public.ops_maybe_run_daily_pipeline()`
- **Invocation:** `SELECT ops_maybe_run_daily_pipeline()`
- **Scheduler:**
  - Schedule: `*/5 9-11 * * *` (every 5 minutes, 09:00–11:55 UTC)
- **Trigger mode:** pg_cron automatic
- **Inputs:** Same as job 29
- **Outputs:** Same as job 29 (gated)
- **Upstream dependencies:** None
- **Downstream consumers:** Same as job 11
- **Env dependencies:** None
- **Storage dependencies:** None
- **Source of truth:** Supabase PostgreSQL function
- **Migration status:** 🔴 Not in monorepo SQL
- **Risk:** 🟢 LOW — gated
- **Notes:** Overlaps time range with job 11. Both are acceptable; `ops_maybe_run_daily_pipeline` guard prevents double execution.

---

#### Job: pg_cron #30 — run_greenhouse_daily_pipeline_full (every minute) ⚠️ DUPLICATE

- **Runtime:** pg_cron
- **Purpose:** **NONE — this is a duplicate of job 39 and an excessive version of job 11.** Should be disabled.
- **Code location:** `public.run_greenhouse_daily_pipeline_full(40, 14, 2)`
- **Invocation:** `SELECT run_greenhouse_daily_pipeline_full(40, 14, 2)`
- **Scheduler:**
  - Schedule: `* * * * *` ← **every minute, 24/7**
- **Trigger mode:** pg_cron automatic
- **Risk:** 🔴 CRITICAL — runs every minute unconditionally. During 10:00–11:55 window, this overlaps with jobs 11 and 39 = 3+ concurrent full ETL invocations per minute. Causes excessive Supabase DB load.
- **Action required:** `SELECT cron.unschedule(30);`
- **Notes:** Identical schedule and function call to job 39. Almost certainly a configuration accident.

---

#### Job: pg_cron #38 — ops_maybe_run_daily_pipeline (every minute) ⚠️ EXCESSIVE

- **Runtime:** pg_cron
- **Purpose:** **Redundant — duplicates jobs 29 and 37 at excessive frequency.**
- **Code location:** `public.ops_maybe_run_daily_pipeline()`
- **Invocation:** `SELECT ops_maybe_run_daily_pipeline()`
- **Scheduler:**
  - Schedule: `* * * * *` ← **every minute, 24/7**
- **Trigger mode:** pg_cron automatic
- **Risk:** 🟠 HIGH — even though gated, the function is called 1440 times/day vs 240 for jobs 29+37 combined. Wastes connections and compute.
- **Action required:** `SELECT cron.unschedule(38);`
- **Notes:** Gate function may protect data correctness but still generates unnecessary DB load.

---

#### Job: pg_cron #39 — run_greenhouse_daily_pipeline_full (every minute) ⚠️ DUPLICATE

- **Runtime:** pg_cron
- **Purpose:** **NONE — exact duplicate of job 30.**
- **Code location:** `public.run_greenhouse_daily_pipeline_full(40, 14, 2)`
- **Invocation:** `SELECT run_greenhouse_daily_pipeline_full(40, 14, 2)`
- **Scheduler:**
  - Schedule: `* * * * *` ← **every minute, 24/7**
- **Trigger mode:** pg_cron automatic
- **Risk:** 🔴 CRITICAL — same as job 30
- **Action required:** `SELECT cron.unschedule(39);`
- **Notes:** Identical to job 30 in every way.

---

### Group: Planner

---

#### Job: pg_cron #12 — core_planner__nightly_roll4_reset

- **Runtime:** pg_cron
- **Purpose:** Reset the rolling 4-week planner window state nightly. Clears stale orchestrator state before tick runs at noon.
- **Code location:** SQL function `public.core_planner__nightly_roll4_reset()`
- **Invocation:** `SELECT core_planner__nightly_roll4_reset()`
- **Scheduler:**
  - Schedule: `5 1 * * *` (01:05 daily)
- **Trigger mode:** pg_cron automatic
- **Inputs:**
  - Tables: `t_core_planner__orchestrator_state`, `t_core_planner__refresh_state`
- **Outputs:**
  - Tables: `t_core_planner__orchestrator_state` (reset), `t_core_planner__refresh_state` (reset)
- **Upstream dependencies:** Must run before job 13 (12:00 tick)
- **Downstream consumers:** pg_cron #13 (noon tick reads reset state)
- **Env dependencies:** None
- **Storage dependencies:** None
- **Source of truth:** Supabase PostgreSQL function
- **Migration status:** 🔴 Not in monorepo SQL
- **Risk:** 🟢 LOW
- **Notes:** Runs at 01:05, 5 minutes after midnight. If this fails, job 13 will operate on stale state.

---

#### Job: pg_cron #13 — core_planner__nightly_roll4_tick

- **Runtime:** pg_cron
- **Purpose:** Advance the rolling 4-week assortment planner. Reads latest forecast results and recomputes planner output tables consumed by the planner API and frontend.
- **Code location:** SQL function `public.core_planner__nightly_roll4_tick(n int)`
- **Invocation:** `SELECT core_planner__nightly_roll4_tick(2)`
- **Scheduler:**
  - Schedule: `0 12 * * *` (12:00 noon daily)
- **Trigger mode:** pg_cron automatic
- **Inputs:**
  - Tables: `greenhouse_forecast_results_v2`, `greenhouse_forecast_features_dense`, `famiglie_catalog_static`
  - Tables: `t_core_planner__params_level`, `t_core_planner__space_budget`, `t_core_planner__potsize_profile`
  - Tables: `t_core_planner__orchestrator_state` (reset by job 12)
- **Outputs:**
  - Tables: `t_core_planner__fact_weekly`, `t_core_planner__heat_cells`, `t_core_planner__assortment_calendar`, `t_core_planner__density`
  - Tables: `t_core_planner__orchestrator_state`, `t_core_planner__refresh_state` (updated)
- **Upstream dependencies:** `gh-predict-all` must have completed (writes `greenhouse_forecast_results_v2` at 01:30–03:00). Job 12 must have reset state.
- **Downstream consumers:** FastAPI `/api/v1/planner` (heat-cells, fact-weekly, space-budget, assortment-calendar, density), frontend Planner page.
- **Env dependencies:** None
- **Storage dependencies:** None
- **Source of truth:** Supabase PostgreSQL function
- **Migration status:** 🔴 Not in monorepo SQL
- **Risk:** 🟡 MEDIUM — if `gh-predict-all` runs late (slow training), this noon tick operates on yesterday's forecast results.
- **Notes:** Parameter `n=2` controls tick step count. Planner data visible in frontend from noon each day.

---

### Group: Monitor Snapshots

All jobs in this group call either `ops_pipeline_monitor_snapshot()` or `ops_refresh_pipeline_monitor_snapshot()`. They are low-risk observability jobs.

---

#### Job: pg_cron #28 — ops_pipeline_monitor_snapshot (continuous)

- **Runtime:** pg_cron
- **Purpose:** Take a periodic snapshot of the pipeline state into `t_ops_pipeline_monitor` for dashboarding and alerting.
- **Code location:** SQL function `public.ops_pipeline_monitor_snapshot()`
- **Invocation:** `SELECT ops_pipeline_monitor_snapshot()`
- **Scheduler:** `*/15 * * * *` (every 15 minutes, 24/7)
- **Trigger mode:** pg_cron automatic
- **Inputs:** Various pipeline state tables (`etl.t_etl_runs`, `ops_parquet_export_state`, `ml_forecast.*`, `ml_ops.*`)
- **Outputs:** `public.t_ops_pipeline_monitor` (append snapshot row)
- **Downstream consumers:** `v_ops_pipeline_monitor_latest` view, FastAPI `/api/v1/ops`
- **Source of truth:** Supabase PostgreSQL function
- **Migration status:** 🔴 Not in monorepo SQL
- **Risk:** 🟢 LOW

---

#### Job: pg_cron #32 — ops_refresh_pipeline_monitor_snapshot (morning)

- **Runtime:** pg_cron
- **Purpose:** Refresh analytics materialized views during morning ETL window when data changes most rapidly.
- **Code location:** SQL function `public.ops_refresh_pipeline_monitor_snapshot()`
- **Invocation:** `SELECT ops_refresh_pipeline_monitor_snapshot()`
- **Scheduler:** `*/2 10-12 * * *` (every 2 minutes, 10:00–12:00)
- **Trigger mode:** pg_cron automatic
- **Inputs:** Underlying tables for `mv_core_analytics__*`, `mv_famiglie_catalog`
- **Outputs:** Refreshed MVs: `mv_core_analytics__catalog_entities`, `mv_core_analytics__series_daily_*` (4 dims), `mv_core_analytics__breakdown_daily_fascia_fp`, `mv_famiglie_catalog`
- **Source of truth:** Supabase PostgreSQL function
- **Migration status:** 🔴 Not in monorepo SQL
- **Risk:** 🟢 LOW

---

#### Job: pg_cron #35 — ops_refresh_pipeline_monitor_snapshot (morning fine)

- **Runtime:** pg_cron
- **Purpose:** Same as job 32, overlapping window at 5-minute cadence for pre-ETL window (09:00–11:55).
- **Code location:** Same as job 32
- **Scheduler:** `*/5 9-11 * * *`
- **Risk:** 🟢 LOW — same function, window overlap with job 32 is harmless if MV refresh is idempotent.

---

#### Job: pg_cron #31 — ops_refresh_pipeline_monitor_snapshot (evening)

- **Runtime:** pg_cron
- **Purpose:** Refresh MVs after evening ETL catch-up window (jobs 29/37/38).
- **Code location:** Same as job 32
- **Scheduler:** `*/10 19-23 * * *`
- **Risk:** 🟢 LOW

---

#### Job: pg_cron #34 — ops_refresh_pipeline_monitor_snapshot (off-hours)

- **Runtime:** pg_cron
- **Purpose:** Low-frequency MV refresh during off-hours (00:00–09:00 and 13:00–23:00, excluding peak windows).
- **Code location:** Same as job 32
- **Scheduler:** `*/30 0-9,13-23 * * *`
- **Risk:** 🟢 LOW

---

## Appendix: Quick Reference Table

### Systemd jobs

| Job | Schedule | Python source (active) | Migration |
|-----|----------|----------------------|-----------|
| `gh-parquet-export` | 21:35 daily | `/opt/greenhouse/repo/jobs/parquet_export/export_features_dense.py` | 🟡 Partial |
| `gh-refresh-registry` | 00:45 daily | `/opt/greenbrain-platform/apps/ml-worker/jobs/refresh_registry.py` | ✅ Migrated |
| `gh-train-missing` | 01:10 daily | `/opt/greenhouse/repo/jobs/train_missing_batches.py` | 🟡 Partial |
| `gh-predict-all` | 01:30 daily | `/opt/greenhouse/repo/jobs/predict_all.py` | 🟡 Partial |
| `gh-train-biweekly-all` | Sun 1st+15th 02:00 | `/opt/greenhouse/repo/jobs/train_all_monitor.py` | 🔴 Not migrated |
| `gh-train-quarterly` | Jan/Apr/Jul/Oct 1st 02:30 | `/opt/greenhouse/repo/jobs/train_all_monitor.py` | 🔴 Not migrated |

### pg_cron jobs

| jobid | Schedule | Function | Status |
|-------|----------|----------|--------|
| 11 | `*/5 10-11 * * *` | `run_greenhouse_daily_pipeline_full(40,14,2)` | ✅ Keep |
| 12 | `5 1 * * *` | `core_planner__nightly_roll4_reset()` | ✅ Keep |
| 13 | `0 12 * * *` | `core_planner__nightly_roll4_tick(2)` | ✅ Keep |
| 28 | `*/15 * * * *` | `ops_pipeline_monitor_snapshot()` | ✅ Keep |
| 29 | `*/5 19-23 * * *` | `ops_maybe_run_daily_pipeline()` | ✅ Keep |
| **30** | `* * * * *` | `run_greenhouse_daily_pipeline_full(40,14,2)` | ⚠️ **DISABLE** |
| 31 | `*/10 19-23 * * *` | `ops_refresh_pipeline_monitor_snapshot()` | ✅ Keep |
| 32 | `*/2 10-12 * * *` | `ops_refresh_pipeline_monitor_snapshot()` | ✅ Keep |
| 34 | `*/30 0-9,13-23 * * *` | `ops_refresh_pipeline_monitor_snapshot()` | ✅ Keep |
| 35 | `*/5 9-11 * * *` | `ops_refresh_pipeline_monitor_snapshot()` | ✅ Keep |
| 37 | `*/5 9-11 * * *` | `ops_maybe_run_daily_pipeline()` | ✅ Keep |
| **38** | `* * * * *` | `ops_maybe_run_daily_pipeline()` | ⚠️ **DISABLE** |
| **39** | `* * * * *` | `run_greenhouse_daily_pipeline_full(40,14,2)` | ⚠️ **DISABLE** |
