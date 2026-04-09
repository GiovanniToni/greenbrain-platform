# Greenbrain — Architecture Map
> Generated: 2026-03-26 | Evidence-based scan of `/opt`

---

## Table of Contents
1. [Repository Layout](#1-repository-layout)
2. [Python Entrypoints](#2-python-entrypoints)
3. [Job Metadata](#3-job-metadata)
4. [Shell Scripts](#4-shell-scripts)
5. [Bin CLI Commands](#5-bin-cli-commands)
6. [Environment Variables](#6-environment-variables)
7. [Scheduling Reference](#7-scheduling-reference)
8. [Backend API Surface](#8-backend-api-surface)
9. [Database Tables Reference](#9-database-tables-reference)
10. [Gaps & Notes](#10-gaps--notes)

---

## 1. Repository Layout

| Path | Role | Status |
|------|------|--------|
| `/opt/greenhouse/repo` | Primary ML worker — train, predict, ETL backfill, parquet export, governance | **Active** |
| `/opt/greenbrain-platform/apps/ml-worker` | Mirror of `/opt/greenhouse/repo` (byte-for-byte identical `jobs/` tree) | Mirror/staging |
| `/opt/greenbrain-v2/backend` | FastAPI REST API (Docker `gb_v2_backend`, port 8002) | **Active** |
| `/opt/greenbrain/frontend` | React + Vite frontend (Supabase + backend :8002) | **Active** |
| `/opt/greenbrain-v2/database` | DB schema SQL baseline + migrations | Reference |
| `/opt/greenbrain-v2/deploy` | Docker Compose + deploy scripts | Ops |
| `/etc/systemd/system/gh-*.{service,timer}` | systemd units for ML jobs | **Active** |

---

## 2. Python Entrypoints

### 2.1 Root scripts — `/opt/greenhouse/repo/`

| # | File | CLI / Style | Scheduled |
|---|------|-------------|-----------|
| 1 | `train_v4_single_family_tweedie.py` | `argparse --family` | Via `train_family_router.py` |
| 2 | `predict_v4_single_family_tweedie.py` | `argparse --family` | Via `predict_family_router.py` |
| 3 | `backfill_fact_weekly.py` | `__main__` | Manual |
| 4 | `backfill_dense_weekly.py` | `__main__` | Manual |
| 5 | `backfill_features_weekly.py` | `__main__` | Manual |
| 6 | `patch_holidays_features_weekly.py` | `__main__` | Manual |
| 7 | `refresh_weekday_strength.py` | `__main__` | Manual |
| 8 | `sync_holidays.py` | `__main__` | Manual |
| 9 | `evaluate_v4_forecast.py` | Inline (no `__main__`) | Manual analysis |
| 10 | `fetch_forecast_dataset.py` | `__main__` | **Legacy** |
| 11 | `fetch_forecast_dataset_v2.py` | `__main__` | **Legacy** |
| 12 | `test_spaces.py` | Inline | Manual test |
| 13 | `backtest_v4_family_plus_fasce.py` | Inline | Manual analysis |
| 14 | `backtest_v4_family_total.py` | Inline | Manual analysis |

### 2.2 Jobs — `/opt/greenhouse/repo/jobs/`

| # | File | CLI / Style | Scheduled |
|---|------|-------------|-----------|
| 15 | `predict_all.py` | `SystemExit(main())` | **systemd** `gh-predict-all.timer` 01:30 UTC |
| 16 | `train_missing_batches.py` | `SystemExit(main())` | **systemd** `gh-train-missing.timer` 01:10 UTC |
| 17 | `train_all_monitor.py` | `SystemExit(main())` | **systemd** biweekly + quarterly timers |
| 18 | `train_all_batches.py` | `__main__` | Manual loop (`run_train_all_until_done.sh`) — **Legacy** |
| 19 | `refresh_registry.py` | `SystemExit(main())` | **systemd** `gh-refresh-registry.timer` 00:45 UTC |
| 20 | `sync_local_artifacts.py` | `SystemExit(main())` | Manual only (`gh-sync-local-artifacts`) — **no timer** |
| 21 | `update_family_state.py` | `argparse --family --action` | Manual CLI |
| 22 | `model_control.py` | `argparse` (multi sub-cmd) | Manual CLI |
| 23 | `validate_engines.py` | `argparse [--write-db]` | Manual / CI |
| 24 | `benchmark_family.py` | `argparse` (multi sub-cmd) | Manual (disabled in `job_schedule_config_v1`) |
| 25 | `diagnose_families.py` | Inline | Manual analysis |
| 26 | `dump_families.py` | `__main__` | Manual utility |
| 27 | `download_priors_from_supabase.py` | `__main__` | Via `run_predict_all.sh` step 4 |
| 28 | `upload_priors_to_supabase.py` | `__main__` | Via `run_predict_all.sh` step 3 |

### 2.3 Parquet export — `/opt/greenhouse/repo/jobs/parquet_export/`

| # | File | CLI / Style | Scheduled |
|---|------|-------------|-----------|
| 29 | `export_features_dense.py` | `SystemExit(main())` | Via `run_daily_parquet_batches.sh` — **no systemd timer** |

### 2.4 Tools — `/opt/greenhouse/repo/tools/`

| # | File | CLI / Style | Scheduled |
|---|------|-------------|-----------|
| 30 | `build_seasonal_priors.py` | `__main__` `--slugs-file` | Via `run_predict_all.sh` step 2 |
| 31 | `hurdle_report.py` | `__main__` | Manual analysis |

### 2.5 Scripts (libraries, not direct entrypoints)

| File | Role |
|------|------|
| `scripts/spaces_io.py` | DO Spaces upload/download via boto3 — imported by `ensure_model_bundle.py` |
| `scripts/patch_get_engine_urlcreate.py` | One-off patch (already applied) |
| `scripts/patch_predict_safe.py` | One-off patch (already applied) |

---

## 3. Job Metadata

### J01 · `train_v4_single_family_tweedie.py`
| | |
|-|-|
| **Path** | `/opt/greenhouse/repo/train_v4_single_family_tweedie.py` |
| **Purpose** | Train LightGBM Tweedie model for one family; save `.pkl` bundle locally |
| **Input tables** | `public.greenhouse_forecast_features_dense` (via `data_access_v1`, parquet-first) |
| **Input storage** | `ml-snapshots/features_dense/v1/year=Y/famiglia_slug=S/part.parquet` |
| **Output files** | `models_v4/bundle_<slug>_v4.pkl` |
| **Output storage** | DO Spaces `models_v4/bundle_<slug>_v4.pkl` (via caller's `upload_bundle`) |
| **Key env vars** | `V4_*`, `ONLY_FAMILY`, `PARQUET_ENABLE`, `DATABASE_URL`, `PG_*` |
| **Called by** | `jobs/train_family_router.py`, `jobs/train_one_safe.sh` |

### J02 · `predict_v4_single_family_tweedie.py`
| | |
|-|-|
| **Path** | `/opt/greenhouse/repo/predict_v4_single_family_tweedie.py` |
| **Purpose** | Load `.pkl` bundle; write forecast for next N days per family+fascia |
| **Input files** | `models_v4/bundle_<slug>_v4.pkl`, `priors_cache/priors_v1.parquet` |
| **Input tables** | `public.greenhouse_forecast_features_dense` (via `load_hist_for_predict_parquet_or_db`) |
| **Output tables** | `public.greenhouse_forecast_results_v2` (UPSERT) |
| **Key env vars** | `V4_ENABLE_HURDLE`, `V4_ENABLE_WINDOW_ANCHOR`, `V4_FAMILY_TOTAL_BETA`, `V4_HORIZON_DAYS`, `ONLY_FAMILY`, `DATABASE_URL` |
| **Called by** | `jobs/predict_family_router.py` |

### J03 · `jobs/predict_all.py`
| | |
|-|-|
| **Path** | `/opt/greenhouse/repo/jobs/predict_all.py` |
| **Purpose** | Daily predict orchestrator for all active families. Checks `job_schedule_config_v1`, lists families from `v_family_execution_routing_v2`, ensures bundle (auto-trains if `AUTO_TRAIN_MISSING=1`), calls `predict_family_router.py` per family |
| **Input tables** | `ml_forecast.v_family_execution_routing_v2`, `ml_ops.job_schedule_config_v1` |
| **Output tables** | `public.greenhouse_forecast_results_v2` (child), `ml_ops.pipeline_run_log_v1`, `ml_ops.family_run_log_v1` |
| **Key env vars** | `AUTO_TRAIN_MISSING`, `PREDICT_LIMIT`, `PREDICT_ONLY_FAMILY`, `PREDICT_FAMILY_TIMEOUT_SEC`, `RUN_TRIGGER_SOURCE`, `GIT_SHA` |
| **Trigger** | `run_predict_all.sh` → **systemd** `gh-predict-all.timer` (`01:30 UTC daily`) |
| **Dependencies** | `jobs/ensure_model_bundle.py`, `jobs/family_resolver.py`, `jobs/ml_ops_bridge.py` |

### J04 · `jobs/train_missing_batches.py`
| | |
|-|-|
| **Path** | `/opt/greenhouse/repo/jobs/train_missing_batches.py` |
| **Purpose** | Train families missing a valid bundle. Queries candidate families, runs `train_family_router.py` per family in batches of `BATCH_SIZE=10`, uploads bundle to DO Spaces |
| **Input tables** | `ml_forecast.v_family_execution_routing_v2`, `ml_ops.job_schedule_config_v1` |
| **Output tables** | `ml_ops.pipeline_run_log_v1`, `ml_ops.family_run_log_v1` |
| **Output storage** | DO Spaces `models_v4/bundle_<slug>_v4.pkl` |
| **State written** | `ml_forecast.family_model_state_v1` via `mark_family_train_success/failed_v1` |
| **Key env vars** | `TRAIN_BATCH_SIZE`, `TRAIN_LIMIT`, `TRAIN_TIMEOUT_SEC`, `PARQUET_ENABLE`, `RUN_TRIGGER_SOURCE`, `GIT_SHA` |
| **Trigger** | `run_train_missing.sh` → **systemd** `gh-train-missing.timer` (`01:10 UTC daily`) |

### J05 · `jobs/train_all_monitor.py`
| | |
|-|-|
| **Path** | `/opt/greenhouse/repo/jobs/train_all_monitor.py` |
| **Purpose** | Train ALL active families in parallel (`TRAIN_ALL_JOBS=4`). Used for biweekly and quarterly full retrains |
| **Input tables** | `ml_forecast.v_family_execution_routing_v2` |
| **Output tables** | `ml_ops.pipeline_run_log_v1` |
| **Output storage** | DO Spaces `models_v4/bundle_<slug>_v4.pkl` (via `train_one_safe.sh`) |
| **Key env vars** | `TRAIN_ALL_JOBS`, `TRAIN_LIMIT`, `TRAIN_ONLY_FAMILY`, `RUN_TRIGGER_SOURCE`, `RUN_TYPE`, `MODEL_VERSION`, `GIT_SHA` |
| **Trigger** | **systemd** `gh-train-biweekly-all.timer` (Sun 1st+15th 02:00 UTC) and `gh-train-quarterly.timer` (Jan/Apr/Jul/Oct 1 02:30 UTC) |

### J06 · `jobs/train_all_batches.py` *(Legacy)*
| | |
|-|-|
| **Path** | `/opt/greenhouse/repo/jobs/train_all_batches.py` |
| **Purpose** | Older batch trainer. Lists families from `FAMIGLIE_SOURCE_TABLE`, trains in batches, uploads bundles. No mlops logging. |
| **Input tables** | `public.mv_famiglie_catalog` (configurable via `FAMIGLIE_SOURCE_TABLE`) |
| **Output storage** | DO Spaces `models_v4/bundle_<slug>_v4.pkl` |
| **Status** | **Legacy** — superseded by `train_missing_batches.py` + `train_all_monitor.py` |
| **Trigger** | `run_train_all_until_done.sh` (manual loop) |

### J07 · `jobs/refresh_registry.py`
| | |
|-|-|
| **Path** | `/opt/greenhouse/repo/jobs/refresh_registry.py` |
| **Purpose** | Refresh ML classification + sync family state. Runs 3 DB functions, then sets `needs_predict=true` for all |
| **Input tables** | `ml_forecast.family_model_registry_v2` |
| **Output tables** | `ml_forecast.family_model_state_v1`, `ml_ops.classification_change_log_v1`, `ml_ops.pipeline_run_log_v1` |
| **DB functions** | `ml_forecast.log_classification_changes_v1()`, `sync_family_model_state_from_registry_v1()`, `sync_family_model_state_from_artifacts_v1()` |
| **Key env vars** | `DATABASE_URL`, `RUN_TRIGGER_SOURCE` |
| **Trigger** | **systemd** `gh-refresh-registry.timer` (`00:45 UTC daily`) |

### J08 · `jobs/sync_local_artifacts.py`
| | |
|-|-|
| **Path** | `/opt/greenhouse/repo/jobs/sync_local_artifacts.py` |
| **Purpose** | Scan local `models_v4/bundle_*_v4.pkl` files; register each in `model_artifact_registry_v1`; update `family_model_state_v1.needs_initial_train/needs_retrain` |
| **Input files** | `models_v4/bundle_*_v4.pkl` (local filesystem) |
| **Input tables** | `ml_forecast.family_model_registry_v2` (resolve model_code) |
| **Output tables** | `ml_forecast.model_artifact_registry_v1`, `ml_forecast.family_model_state_v1`, `ml_ops.pipeline_run_log_v1` |
| **Key env vars** | `DATABASE_URL`, `MODEL_DIR_V4`, `REPO_DIR`, `RUN_TRIGGER_SOURCE` |
| **Status** | **No timer** — manual only (`gh-sync-local-artifacts`). Should run after train. |

### J09 · `jobs/update_family_state.py`
| | |
|-|-|
| **Path** | `/opt/greenhouse/repo/jobs/update_family_state.py` |
| **Purpose** | CLI to mark train/predict success or failure for a single family |
| **CLI** | `--family <name> --action {train_success,train_failed,predict_success,predict_failed} [--run-id N] [--model-code X] [--message M]` |
| **Output tables** | `ml_forecast.family_model_state_v1` (via DB functions) |
| **DB functions** | `ml_forecast.mark_family_train_success_v1`, `mark_family_train_failed_v1`, `mark_family_predict_success_v1`, `mark_family_predict_failed_v1` |
| **Key env vars** | `DATABASE_URL` |
| **Status** | Manual repair tool only |

### J10 · `jobs/model_control.py`
| | |
|-|-|
| **Path** | `/opt/greenhouse/repo/jobs/model_control.py` |
| **Purpose** | Governance CLI: assign models to families/classes. Sets `needs_retrain=true` + `needs_predict=true`. Writes immutable audit log. Respects `is_locked`. |
| **CLI sub-commands** | `assign-model-to-family`, `assign-model-to-class`, `assign-model-to-all`, `apply-best-suggested-model` |
| **Input tables** | `ml_forecast.family_model_assignment_v1`, `ml_forecast.model_catalog_v1`, `ml_forecast.v_family_execution_routing_v2` |
| **Output tables** | `ml_forecast.family_model_assignment_v1`, `ml_forecast.family_model_assignment_log_v1`, `ml_forecast.family_model_state_v1` |
| **Key env vars** | `DATABASE_URL`, `GH_REPO_DIR` |
| **Status** | Manual governance tool only |

### J11 · `jobs/validate_engines.py`
| | |
|-|-|
| **Path** | `/opt/greenhouse/repo/jobs/validate_engines.py` |
| **Purpose** | End-to-end validation of all forecast engines (Croston, ETS, TSB, SARIMA, NAIVE_ZERO). Selects one sample family per model code, runs predict, validates output schema. |
| **CLI** | `[--write-db]` |
| **Input tables** | `ml_forecast.family_model_registry_v2`, `ml_forecast.family_model_state_v1`, `ml_forecast.v_family_execution_routing_v1` |
| **Output tables** | None by default; `--write-db` writes to forecast tables |
| **Status** | Manual / CI. Not scheduled. |

### J12 · `jobs/benchmark_family.py`
| | |
|-|-|
| **Path** | `/opt/greenhouse/repo/jobs/benchmark_family.py` |
| **Purpose** | Offline benchmark: holdout mode comparison of models. Computes WMAPE/MAE/RMSE/BIAS. Writes suggestions. **Never modifies production assignment or bundles.** |
| **CLI sub-commands** | `benchmark-one-family`, `benchmark-many-families`, `benchmark-new-families`, `benchmark-all-families` |
| **Input tables** | `greenhouse_forecast_features_dense` (parquet-first), `ml_forecast.family_model_registry_v2`, `ml_forecast.family_model_assignment_v1` |
| **Output tables** | `ml_forecast.family_model_benchmark_v1`, `ml_forecast.family_model_suggestion_benchmark_v1` |
| **Status** | `job_schedule_config_v1`: `benchmark_weekly=disabled`. Manual only. |

### J13 · `jobs/parquet_export/export_features_dense.py`
| | |
|-|-|
| **Path** | `/opt/greenhouse/repo/jobs/parquet_export/export_features_dense.py` |
| **Purpose** | Export `greenhouse_forecast_features_dense` to per-family per-year parquet files and upload to Supabase Storage. Supports batching (`BATCH_SIZE/BATCH_OFFSET`), full export (`FULL_EXPORT=1`), single-family (`ONLY_FAMILY_SLUG`), single-year (`ONLY_YEAR`). |
| **Input tables** | `public.greenhouse_forecast_features_dense`, `public.ops_parquet_export_state` |
| **Output storage** | `ml-snapshots/features_dense/v1/year=YYYY/famiglia_slug=<slug>/part.parquet` |
| **Output tables** | `public.ops_parquet_export_runs` (run log), `public.ops_parquet_export_state` (last success) |
| **Key env vars** | `DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_BUCKET`, `BATCH_SIZE`, `BATCH_OFFSET`, `FULL_EXPORT`, `ONLY_FAMILY_SLUG`, `ONLY_YEAR`, `UPLOAD_MAX_RETRIES`, `UPLOAD_BASE_BACKOFF_SEC`, `QUERY_MAX_RETRIES`, `PROGRESS_EVERY`, `COMMIT_EVERY_FILES`, `GB_ENV_FILE` |
| **Status** | **No systemd timer.** `ops_parquet_export_state` shows last run 2026-03-21 17:50. Trigger is `run_daily_parquet_batches.sh` (manual). |

### J14 · `jobs/download_priors_from_supabase.py`
| | |
|-|-|
| **Path** | `/opt/greenhouse/repo/jobs/download_priors_from_supabase.py` |
| **Purpose** | Download `priors_v1.parquet` from Supabase Storage to local cache |
| **Input storage** | `ml-snapshots/priors/priors_v1.parquet` |
| **Output files** | `$PRIORS_LOCAL_PATH` (default: `priors_cache/priors_v1.parquet`) |
| **Key env vars** | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_BUCKET`, `PRIORS_LOCAL_PATH`, `PRIORS_REMOTE_PATH` |
| **Trigger** | Step 4 of `run_predict_all.sh` |

### J15 · `jobs/upload_priors_to_supabase.py`
| | |
|-|-|
| **Path** | `/opt/greenhouse/repo/jobs/upload_priors_to_supabase.py` |
| **Purpose** | Upload locally-built `priors_v1.parquet` to Supabase Storage. Tries `update` then `upload` for supabase-py compat. |
| **Input files** | `$PRIORS_LOCAL_PATH` |
| **Output storage** | `ml-snapshots/priors/priors_v1.parquet` |
| **Key env vars** | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_BUCKET`, `PRIORS_LOCAL_PATH`, `PRIORS_REMOTE_PATH` |
| **Trigger** | Step 3 of `run_predict_all.sh` |

### J16 · `tools/build_seasonal_priors.py`
| | |
|-|-|
| **Path** | `/opt/greenhouse/repo/tools/build_seasonal_priors.py` |
| **Purpose** | Build seasonal prior distributions (day-of-year demand profiles). Queries `greenhouse_forecast_features_dense`, smooths, outputs `priors_v1.parquet`. |
| **CLI** | `--slugs-file <path>` |
| **Input tables** | `public.greenhouse_forecast_features_dense` (or parquet cache) |
| **Output files** | `$PRIORS_LOCAL_PATH` |
| **Key env vars** | `V4_PRIOR_SMOOTH_DOY`, `PARQUET_ENABLE`, `DATABASE_URL`, `GH_PRIORS_DIR` |
| **Trigger** | Step 2 of `run_predict_all.sh` |

### J17 · `backfill_fact_weekly.py`
| | |
|-|-|
| **Purpose** | Backfill `greenhouse_sales_family_daily_fact` from view `greenhouse_sales_family_daily_v2` in weekly chunks with progress file + retry |
| **Input tables** | `public.greenhouse_sales_family_daily_v2` (view) |
| **Output tables** | `public.greenhouse_sales_family_daily_fact` (ON CONFLICT DO UPDATE) |
| **Key env vars** | `PG_HOST`, `PG_PORT`, `PG_DB`, `PG_USER`, `PG_PASSWORD` |

### J18 · `backfill_dense_weekly.py`
| | |
|-|-|
| **Purpose** | Backfill `greenhouse_sales_family_daily_dense` via `refresh_dense_range()` in weekly chunks |
| **Input tables** | `public.greenhouse_sales_family_daily_fact` (via SQL function) |
| **Output tables** | `public.greenhouse_sales_family_daily_dense` |
| **DB functions** | `public.refresh_dense_range(start, end)` |
| **Key env vars** | `PG_HOST`, `PG_PORT`, `PG_DB`, `PG_USER`, `PG_PASSWORD` |

### J19 · `backfill_features_weekly.py`
| | |
|-|-|
| **Purpose** | Backfill `greenhouse_forecast_features_dense` via `refresh_forecast_features_dense_range()` in 7-day chunks |
| **Input tables** | `public.greenhouse_sales_family_daily_dense` (via SQL function) |
| **Output tables** | `public.greenhouse_forecast_features_dense` |
| **DB functions** | `public.refresh_forecast_features_dense_range(start, end)` |
| **Key env vars** | `PG_HOST`, `PG_PORT`, `PG_DB`, `PG_USER`, `PG_PASSWORD`, `STATEMENT_TIMEOUT_MS` |

### J20 · `patch_holidays_features_weekly.py`
| | |
|-|-|
| **Purpose** | Backfill/patch `is_holiday`/`holiday_name` in `greenhouse_forecast_features_dense` by joining with `greenhouse_holidays` |
| **Input tables** | `public.greenhouse_holidays`, `public.greenhouse_forecast_features_dense` |
| **Output tables** | `public.greenhouse_forecast_features_dense` (UPDATE) |
| **Key env vars** | `PG_HOST`, `PG_PORT`, `PG_DB`, `PG_USER`, `PG_PASSWORD`, `STATEMENT_TIMEOUT_MS` |

### J21 · `refresh_weekday_strength.py`
| | |
|-|-|
| **Purpose** | Compute + upsert weekday demand strength (global + per-family) with shrinkage toward 1 |
| **Input tables** | `public.greenhouse_sales_family_daily_v2` |
| **Output tables** | `public.greenhouse_weekday_strength`, `public.greenhouse_weekday_strength_family` |
| **Key env vars** | `STRENGTH_SHRINK_K`, `PG_HOST`, `PG_PORT`, `PG_DB`, `PG_USER`, `PG_PASSWORD` |

### J22 · `sync_holidays.py`
| | |
|-|-|
| **Purpose** | Fetch Italian public holidays from Nager.at REST API (years 2009→current+2) + local holidays (Firenze + Pistoia). Upserts into `greenhouse_holidays`. |
| **Input** | External: `https://date.nager.at/api/v3/PublicHolidays/{year}/IT` |
| **Output tables** | `public.greenhouse_holidays` |
| **Key env vars** | `PG_HOST`, `PG_PORT`, `PG_DB`, `PG_USER`, `PG_PASSWORD` |

### J23 · `jobs/diagnose_families.py`
| | |
|-|-|
| **Purpose** | Generate CSV diagnostic report for all families: days_total, pos_days, zero_rate, qty_total, demand statistics |
| **Input tables** | `public.greenhouse_forecast_features_dense` |
| **Output files** | `diagnostics/families_report_*.csv` |
| **Key env vars** | `DATABASE_URL` |

---

## 4. Shell Scripts

### `/opt/greenhouse/repo/jobs/run_predict_all.sh`
- **Trigger:** systemd `gh-predict-all.timer` → `01:30 UTC daily`
- **Steps:** (1) flock lock; (2) load `.env`; (3) set `RUN_TRIGGER_SOURCE`, `GIT_SHA`; (4) `psql` → slugs from `famiglie_catalog_static`; (5) `build_seasonal_priors.py`; (6) `upload_priors_to_supabase.py`; (7) `download_priors_from_supabase.py`; (8) `predict_all.py`
- **Log:** `logs/predict_all_<stamp>.log` + symlink `predict_all_latest.log`

### `/opt/greenhouse/repo/jobs/run_train_missing.sh`
- **Trigger:** systemd `gh-train-missing.timer` → `01:10 UTC daily`
- **Steps:** (1) flock lock; (2) load venv + `.env`; (3) `python jobs/train_missing_batches.py`
- **Log:** `logs/train_missing_<stamp>.log` + symlink

### `/opt/greenhouse/repo/jobs/run_train_all_parallel.sh`
- **Trigger:** Manual only (requires pre-built `$BASE/tmp/families.txt`)
- **Steps:** flock lock → `xargs -P $JOBS` parallel `train_one_safe.sh "{family}"` per line
- **Status:** Manual. Superseded by `train_all_monitor.py`.

### `/opt/greenhouse/repo/jobs/run_train_all_until_done.sh`
- **Trigger:** Manual loop
- **Steps:** flock lock → loop `python jobs/train_all_batches.py`; break when `trained=0` in log
- **Status:** Uses legacy `train_all_batches.py`. Manual only.

### `/opt/greenhouse/repo/jobs/run_train_missing_until_done.sh`
- **Trigger:** Manual loop
- **Steps:** Loop `run_train_missing.sh` until log shows `batch=0`

### `/opt/greenhouse/repo/jobs/train_one_safe.sh`
- **Trigger:** Called by `run_train_all_parallel.sh`, `gh-train-one`, `train_all_monitor.py` (indirect)
- **Steps:** (1) Resolve family name/slug/demand_class/model_code via DB; (2) Start mlops pipeline+family run; (3) Up to 3 attempts: `python jobs/train_family_router.py --family <name>`; (4) On success: `upload_bundle(slug)` → DO Spaces; (5) mlops finish_ok or finish_fail
- **Log:** `logs/train_all_parallel/<slug>_<ts>.log`

### `/opt/greenhouse/repo/jobs/parquet_export/check_etl_ready.sh`
- **Purpose:** Guard check. Exits 0 if ETL ran successfully for today's raw_last date within last 12 hours
- **Input tables:** `public.greenhouse_sales_raw`, `etl.t_etl_runs`
- **Key env vars:** `PG_HOST`, `PG_PORT`, `PG_DB`, `PG_USER`, `PG_PASSWORD`, `PG_SSLMODE`

### `/opt/greenhouse/repo/jobs/parquet_export/scripts/run_daily_parquet_batches.sh`
- **Purpose:** Run `export_features_dense.py` in offset batches of 50 (0..800), 4 retries each, mkdir lock
- **Config:** `BATCH_SIZE=50`, `MAX_RETRIES_PER_BATCH=4`, `SLEEP_BETWEEN_RETRIES_SEC=20`
- **Log:** `logs/parquet_export/daily_<ts>.log` + per-batch logs
- **Status:** **No systemd timer configured.** Runs manually or ad-hoc.

### `/opt/greenbrain-v2/deploy/scripts/`

| Script | Command |
|--------|---------|
| `up-dev.sh` | `docker compose -f docker-compose.dev.yml up -d` |
| `down-dev.sh` | `docker compose -f docker-compose.dev.yml down` |
| `up-client.sh` | `docker compose -f docker-compose.client.yml up -d` |
| `down-client.sh` | `docker compose -f docker-compose.client.yml down` |
| `reset-client.sh` | down + prune + up |
| `status-dev.sh` / `status-client.sh` | `docker compose ps` |
| `logs-dev.sh` / `logs-client.sh` | tail Docker logs |
| `healthcheck.sh` | `curl /health` against backend |

---

## 5. Bin CLI Commands

All in `/opt/greenhouse/bin/`. Auto-source `.env` and activate venv.

| Command | Invokes | Notes |
|---------|---------|-------|
| `gh-predict-all` | `jobs/predict_all.py` | `RUN_TRIGGER_SOURCE=manual` |
| `gh-predict-all-now` | `jobs/predict_all.py` | Immediate |
| `gh-predict-all-test` | `jobs/predict_all.py` | Limited families |
| `gh-predict-family <fam>` | `jobs/predict_family_router.py --family $1` | Single-family |
| `gh-train-missing` | `jobs/train_missing_batches.py` | `TRAIN_ONLY_FAMILY` unset |
| `gh-train-all <N> <jobs>` | `jobs/train_all_monitor.py` | `TRAIN_LIMIT=$N`, `TRAIN_ALL_JOBS=$jobs`, `RUN_TYPE=train_all_biweekly_manual` |
| `gh-train-all-now` | `jobs/train_all_monitor.py` | Immediate |
| `gh-train-all-test` | `jobs/train_all_monitor.py` | `TRAIN_LIMIT=2` |
| `gh-train-biweekly-all` | `jobs/train_all_monitor.py` | Used by systemd service |
| `gh-train-family <fam>` | `jobs/train_family_router.py --family $1` | Single-family train |
| `gh-train-one <fam>` | `jobs/train_one_safe.sh $1` | Train with retry + upload |
| `gh-refresh-registry` | `jobs/refresh_registry.py` | Used by systemd service |
| `gh-sync-local-artifacts` | `jobs/sync_local_artifacts.py` | Manual only |
| `gh-refresh-ml-diag` | `psql` REFRESH MATERIALIZED VIEW | Refreshes all `ml_diag.*` MVs |
| `gh-monitor` | `psql` queries on `ml_monitor.*` | Shows model states, stale families, recent runs |
| `gh-audit` | systemd timer checks | Audit: timers + recent run status |
| `gh-audit-ops` | `psql` queries on `ml_ops.*` | Recent pipeline + family runs |

---

## 6. Environment Variables

### 6.1 Database Connection

| Variable | Default | Used by |
|----------|---------|---------|
| `DATABASE_URL` | *(required)* | All ML jobs (psycopg3 / SQLAlchemy) |
| `PG_HOST` | *(required)* | Backfill + legacy scripts |
| `PG_PORT` | `5432` | Backfill + legacy scripts |
| `PG_DB` | *(required)* | Backfill + legacy scripts |
| `PG_USER` | *(required)* | Backfill + legacy scripts |
| `PG_PASSWORD` | *(required)* | Backfill + legacy scripts |
| `PG_SSLMODE` | `require` | All scripts |
| `SUPABASE_DB_HOST/PORT/NAME/USER/PASSWORD` | — | Alias compat for export scripts |

### 6.2 Supabase Storage

| Variable | Default | Used by |
|----------|---------|---------|
| `SUPABASE_URL` | *(required)* | `export_features_dense.py`, priors upload/download, `data_access_v1.py` |
| `SUPABASE_SERVICE_ROLE_KEY` | *(required)* | Same |
| `SUPABASE_KEY` | — | Fallback alias in `data_access_v1.py` |
| `SUPABASE_BUCKET` | `ml-snapshots` | All Supabase Storage ops |
| `SUPABASE_HTTP_TIMEOUT_SEC` | — | `export_features_dense.py` upload timeout |

### 6.3 DO Spaces (model bundles)

| Variable | Default | Used by |
|----------|---------|---------|
| `DO_SPACES_REGION` | *(required)* | `scripts/spaces_io.py` |
| `DO_SPACES_BUCKET` | *(required)* | `scripts/spaces_io.py` |
| `DO_SPACES_KEY` | *(required)* | `scripts/spaces_io.py` |
| `DO_SPACES_SECRET` | *(required)* | `scripts/spaces_io.py` |
| `SPACES_PREFIX` | `models_v4` | `jobs/ensure_model_bundle.py` (bundle key prefix) |

### 6.4 Paths

| Variable | Default | Used by |
|----------|---------|---------|
| `GH_REPO_DIR` | `/opt/greenhouse/repo` | Most jobs |
| `GH_LOG_DIR` | `/opt/greenhouse/logs` | `predict_all.py` |
| `GH_PRIORS_DIR` | — | `build_seasonal_priors.py` |
| `GH_PARQUET_CACHE` | — | Cache dir override |
| `MODEL_DIR_V4` | `{REPO_DIR}/models_v4` | `sync_local_artifacts.py`, `ensure_model_bundle.py` |
| `PARQUET_CACHE_DIR` | `{REPO_DIR}/parquet_cache` | `data_access_v1.py` |
| `PRIORS_LOCAL_PATH` | `priors_cache/priors_v1.parquet` | Priors upload/download |
| `PRIORS_REMOTE_PATH` | `priors/priors_v1.parquet` | Priors Storage path |
| `GB_ENV_FILE` | `/opt/greenhouse/.env` | `run_daily_parquet_batches.sh` |

### 6.5 Parquet Export

| Variable | Default | Used by |
|----------|---------|---------|
| `PARQUET_ENABLE` | `1` | `data_access_v1.py`, `train_missing_batches.py` |
| `PARQUET_DATASET_PREFIX` | — | Export prefix (`.env`) |
| `FULL_EXPORT` | unset | `export_features_dense.py` (set = export all years) |
| `BATCH_SIZE` | `50` | `export_features_dense.py` |
| `BATCH_OFFSET` | `0` | `export_features_dense.py` |
| `ONLY_YEAR` | — | `export_features_dense.py` |
| `ONLY_FAMILY_SLUG` | — | `export_features_dense.py` |
| `COMMIT_EVERY_FILES` | — | `export_features_dense.py` |
| `PROGRESS_EVERY` | — | `export_features_dense.py` |
| `UPLOAD_MAX_RETRIES` / `UPLOAD_BASE_BACKOFF_SEC` | — | `export_features_dense.py` |
| `QUERY_MAX_RETRIES` | — | `export_features_dense.py` |

### 6.6 ML Job Control

| Variable | Default | Used by |
|----------|---------|---------|
| `RUN_TRIGGER_SOURCE` | `manual` | All jobs → `pipeline_run_log_v1.trigger_mode` |
| `RUN_TYPE` | `train_all_quarterly` | `train_all_monitor.py` |
| `GIT_SHA` | from `git rev-parse --short HEAD` | Run scripts |
| `MODEL_VERSION` | `v4` | `train_all_monitor.py` |
| `AUTO_TRAIN_MISSING` | `1` | `predict_all.py` |
| `PREDICT_LIMIT` | `0` | `predict_all.py` |
| `PREDICT_ONLY_FAMILY` | — | `predict_all.py` |
| `PREDICT_FAMILY_TIMEOUT_SEC` | `1800` | `predict_all.py` |
| `TRAIN_BATCH_SIZE` | `10` | `train_missing_batches.py` |
| `TRAIN_LIMIT` | `0` | `train_missing_batches.py`, `train_all_monitor.py` |
| `TRAIN_TIMEOUT_SEC` | `7200` | `train_missing_batches.py` |
| `TRAIN_ONLY_FAMILY` | — | `train_all_monitor.py` |
| `TRAIN_ALL_JOBS` | `4` | `train_all_monitor.py` |
| `ONLY_FAMILY` | — | `train_v4_*.py`, `predict_v4_*.py` |
| `FAMIGLIE_SOURCE_TABLE` | `public.mv_famiglie_catalog` | `train_all_batches.py` |
| `FAMIGLIE_COL` | `famiglia` | `train_all_batches.py` |
| `STATEMENT_TIMEOUT_MS` | `600000` | Backfill scripts |

### 6.7 V4 Model Parameters

| Variable | Default | Notes |
|----------|---------|-------|
| `V4_VALID_DAYS` | `30` | Validation window |
| `V4_MIN_TRAIN_ROWS` | `500` | Min rows to train |
| `V4_TWEEDIE_POWER_GRID` | `1.1,...,1.7` | Power search grid |
| `V4_HORIZON_DAYS` | — | Forecast horizon |
| `V4_LGBM_ESTIMATORS` | — | LightGBM n_estimators |
| `V4_LGBM_LR` | — | Learning rate |
| `V4_LGBM_NUM_LEAVES` | — | Num leaves |
| `V4_LGBM_EARLY_STOP` | — | Early stopping |
| `V4_ENABLE_HURDLE` | `0` | Hurdle model |
| `V4_HURDLE_P_FLOOR/CAP/POWER` | `0.0/0.95/2.0` | Hurdle params |
| `V4_HURDLE_DEBUG` | `0` | Hurdle debug |
| `V4_ENABLE_WINDOW_ANCHOR` | `1` | Window anchor |
| `V4_FAMILY_TOTAL_BETA` | `1.0` | Global family scaling |
| `V4_ENABLE_WEEKEND_REBALANCE` | — | Weekend rebalance |
| `V4_ENABLE_DOY_GATE` | — | DOY gate |
| `V4_DOY_GATE_MODE` | — | `soft` or `hard` |
| `V4_SEASONAL_GATE` | — | Seasonal gate |
| `V4_ENABLE_MICRO_CAP` | — | Micro-cap capping |
| `V4_ENABLE_PRESEASON_WARMUP` | — | Pre-season warmup |
| `V4_MIN_DATE` | — | Min training date |
| `V4_PRIOR_SMOOTH_DOY` | `7` | Priors smoothing window |
| `V4_TRAIN_FAMILY_LEVEL` | — | Family-level training |

### 6.8 Per-engine Parameters

| Variable | Engine | Notes |
|----------|--------|-------|
| `ETS_HORIZON_DAYS` | ETS | — |
| `CROSTON_ALPHA` / `CROSTON_HORIZON_DAYS` | Croston | — |
| `SEASONAL_CROSTON_ALPHA/HORIZON_DAYS/MIN_MONTHS` | Seasonal Croston | — |
| `TSB_ALPHA` / `TSB_BETA` / `TSB_HORIZON_DAYS` | TSB | — |
| `SARIMA_HORIZON_DAYS` | SARIMA | — |
| `NAIVE_ZERO_HORIZON_DAYS` | Naive Zero | — |

### 6.9 Backend (`/opt/greenbrain-v2/backend`)

| Variable | Default | Notes |
|----------|---------|-------|
| `POSTGRES_HOST` | `postgres` | pydantic-settings (`core/config.py`) |
| `POSTGRES_PORT` | `5432` | — |
| `POSTGRES_DB` | `greenbrain` | — |
| `POSTGRES_USER` | `greenbrain` | — |
| `POSTGRES_PASSWORD` | `greenbrain` | — |
| `POSTGRES_SSLMODE` | `disable` | — |
| `APP_NAME` / `APP_ENV` / `APP_HOST` / `APP_PORT` | `GreenBrain Backend` / `development` / `0.0.0.0` / `8000` | — |

### 6.10 Frontend (`/opt/greenbrain/frontend/.env`)

| Variable | Value |
|----------|-------|
| `VITE_SUPABASE_PROJECT_ID` | `xbyhmzrlycixxrfjggvn` |
| `VITE_SUPABASE_URL` | `https://xbyhmzrlycixxrfjggvn.supabase.co` |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | `eyJ...` (anon key) |
| `VITE_API_BASE_URL` | `http://127.0.0.1:8002` |

---

## 7. Scheduling Reference

### 7.1 systemd timers (all `active (waiting)` as of 2026-03-21)

| Timer | Schedule (UTC) | Service | Script | Last Run |
|-------|---------------|---------|--------|----------|
| `gh-refresh-registry.timer` | `00:45 daily` | `gh-refresh-registry.service` | `jobs/refresh_registry.py` | 2026-03-21 00:45 |
| `gh-train-missing.timer` | `01:10 daily` | `gh-train-missing.service` | `run_train_missing.sh` | 2026-03-21 01:10 |
| `gh-predict-all.timer` | `01:30 daily` | `gh-predict-all.service` | `run_predict_all.sh` | 2026-03-21 01:30 |
| `gh-train-biweekly-all.timer` | `Sun *-*-01,15 02:00` | `gh-train-biweekly-all.service` | `jobs/train_all_monitor.py` | 2026-03-15 |
| `gh-train-quarterly.timer` | `*-01,04,07,10-01 02:30` | `gh-train-quarterly.service` | `jobs/train_all_monitor.py` | 2026-02-22 |

All services: `EnvironmentFile=/opt/greenhouse/.env`, `WorkingDirectory=/opt/greenhouse/repo`, `User=gh`

### 7.2 pg_cron jobs (Supabase cloud DB)

**Active:**

| Job | Schedule | Command |
|-----|----------|---------|
| `ops_auto_run_after_raw_q5m` | `*/5 19-23 * * *` | `ops_maybe_run_daily_pipeline()` → `run_greenhouse_daily_pipeline_full(40,14,2)` |
| `ops_pipeline_monitor_q5m` | `*/10 19-23 * * *` | `ops_refresh_pipeline_monitor_snapshot()` |
| `planner_roll4_tick_q15m` | `0 12 * * *` | `core_planner__nightly_roll4_tick(2)` |

**Inactive** (defined, `active=false`):

| Job | Schedule | Command |
|-----|----------|---------|
| `greenhouse_daily_full` | `*/5 10-11 * * *` | `run_greenhouse_daily_pipeline_full(40,14,2)` |
| `one_shot_call_pipeline_direct` | `* * * * *` | `run_greenhouse_daily_pipeline_full(40,14,2)` |
| `one_shot_gate_test` | `* * * * *` | `run_greenhouse_daily_pipeline_full(40,14,2)` |
| `one_shot_manual_pipeline_run` | `* * * * *` | `ops_maybe_run_daily_pipeline()` |
| `ops_maybe_run_daily_5m_10_12_rome` | `*/5 9-11 * * *` | `ops_maybe_run_daily_pipeline()` |
| `ops_monitor_5m_10_12_rome` | `*/5 9-11 * * *` | `ops_refresh_pipeline_monitor_snapshot()` |
| `planner_roll4_reset_nightly` | `5 1 * * *` | `core_planner__nightly_roll4_reset()` |

### 7.3 ETL trigger chain

```
ops_auto_run_after_raw_q5m  (*/5 19-23 UTC)
  └─ ops_maybe_run_daily_pipeline()          gate: raw stable >20min + not already done
       └─ run_greenhouse_daily_pipeline_full(rebuild=40, buf=14, roll4=2)
            ├─ A)  detect_target_last  →  MAX(data_movimento) from greenhouse_sales_raw
            ├─ A2) raw_stable_gate_20m
            ├─ B)  daily_etl_postprocess_v3(40)
            │       ├─ greenhouse_sales_raw → greenhouse_sales_family_daily_fact
            │       ├─ refresh_dense_range_from_fact → greenhouse_sales_family_daily_dense
            │       ├─ refresh_forecast_features_dense_range → greenhouse_forecast_features_dense
            │       └─ refresh_analytics_aggregates_range
            ├─ B2) dashboard_refresh_from_dense → dashboard serving tables
            ├─ C0) REFRESH MATERIALIZED VIEW mv_core_analytics__breakdown_daily_fascia_fp
            ├─ C)  refresh_analytics_rollups_range → mv_core_analytics__series_daily_*
            ├─ D)  SKIPPED
            ├─ E)  refresh_planner_week_and_roll4_tick (legacy tick)
            └─ E2) core_planner__refresh_after_import_step
                    ├─ core_planner__refresh_fact_weekly → t_core_planner__fact_weekly
                    ├─ core_planner__refresh_heat_week_step → t_core_planner__heat_cells
                    ├─ core_planner__refresh_potsize_profile → t_core_planner__potsize_profile
                    ├─ core_planner__refresh_space_budget (week + roll4) → t_core_planner__space_budget
                    └─ core_planner__refresh_assortment_calendar (week + roll4) → t_core_planner__assortment_calendar

planner_roll4_tick_q15m  (0 12 * * *)
  └─ core_planner__nightly_roll4_tick(2) → t_core_planner__heat_cells (roll4)
```

---

## 8. Backend API Surface

Base URL: `http://127.0.0.1:8002` (Docker `gb_v2_backend`)

| Router | Prefix | Key Endpoints |
|--------|--------|---------------|
| health | `/health` | `GET /health` |
| system | `/api/v1/system` | DB info, version |
| catalog | `/api/v1/catalog` | hierarchy, `/children` |
| sales | `/api/v1/sales` | sales data |
| analytics | `/api/v1/analytics` | `/series`, `/compare-series`, `/entity-summary`, `/components`, `/seasonality`, `/series-bounds`, `/stock-and-reorder`, `/future-windows-stats` |
| forecast | `/api/v1/forecast` | `/summary`, `/sample`, `/series` |
| planner | `/api/v1/planner` | `/current-week`, `/heatmap-nodes`, `/heatmap-cells`, `/heatmap-week-ranges`, `/heatmap-roll4-ranges`, `/space-budget`, `/assortment-calendar`, `/assortment-calendar-export`, `/order-suggestions`, `/calendar-events` |
| dashboard | `/api/v1/dashboard` | `/sales-weekly`, `/sales-monthly`, `/sales-yearly`, `/reorder-suggestions` |
| ops | `/api/v1/ops` | `/health`, `/pipeline-status`, `/family-runs` |

---

## 9. Database Tables Reference

### Core sales (`public`)

| Table | Populated by |
|-------|-------------|
| `greenhouse_sales_raw` | External import (gestionale/POS — outside workspace) |
| `greenhouse_sales_family_daily_fact` | `daily_etl_postprocess_v3()`, `backfill_fact_weekly.py` |
| `greenhouse_sales_family_daily_dense` | `refresh_dense_range_from_fact()`, `backfill_dense_weekly.py` |
| `greenhouse_forecast_features_dense` | `refresh_forecast_features_dense_range()`, `backfill_features_weekly.py` |
| `greenhouse_forecast_results_v2` | `predict_v4_single_family_tweedie.py` |
| `greenhouse_holidays` | `sync_holidays.py` |
| `greenhouse_weekday_strength` | `refresh_weekday_strength.py` |
| `greenhouse_weekday_strength_family` | `refresh_weekday_strength.py` |

### Analytics (`public`)

| Table/MV | Populated by |
|----------|-------------|
| `mv_core_analytics__breakdown_daily_fascia_fp` | ETL step C0 `REFRESH MATERIALIZED VIEW` |
| `mv_core_analytics__series_daily_famiglia/categoria/fascia/fascia_prezzo` | `refresh_analytics_rollups_range()` step C |
| `t_core_analytics__breakdown_daily_fascia_fp_v2` | `refresh_analytics_rollups_range()` |

### Planner (`public`)

| Table | Populated by |
|-------|-------------|
| `t_core_planner__fact_weekly` | `core_planner__refresh_fact_weekly()` |
| `t_core_planner__heat_cells` | `core_planner__refresh_heat_week_step()` |
| `t_core_planner__potsize_profile` | `core_planner__refresh_potsize_profile()` |
| `t_core_planner__space_budget` | `core_planner__refresh_space_budget()` |
| `t_core_planner__assortment_calendar` | `core_planner__refresh_assortment_calendar()` |

### ML governance (`ml_forecast`)

| Table | Written by |
|-------|-----------|
| `family_model_registry_v2` | `ml_forecast.refresh_family_model_registry_v2()` (reads `ml_diag` MVs) |
| `family_model_assignment_v1` | `jobs/model_control.py` |
| `family_model_assignment_log_v1` | `jobs/model_control.py` (immutable audit) |
| `family_model_state_v1` | `jobs/refresh_registry.py`, `jobs/sync_local_artifacts.py`, `ml_ops_bridge.py` |
| `model_artifact_registry_v1` | `jobs/sync_local_artifacts.py` |
| `family_model_benchmark_v1` | `jobs/benchmark_family.py` |
| `family_model_suggestion_benchmark_v1` | `jobs/benchmark_family.py` |
| `v_family_execution_routing_v2` | VIEW (joins registry + state + assignment) |

### ML ops (`ml_ops`)

| Table | Written by |
|-------|-----------|
| `pipeline_run_log_v1` | All orchestrators via `ml_ops_bridge.py` |
| `family_run_log_v1` | `train_one_safe.sh`, `train_missing_batches.py`, `predict_all.py` |
| `job_schedule_config_v1` | Schema seed — read by `check_job_enabled()` |
| `classification_change_log_v1` | `ml_forecast.log_classification_changes_v1()` |

### ETL tracking (`etl`)

| Table | Written by |
|-------|-----------|
| `t_etl_runs` | `etl._start_run()` / `etl._end_run()` in `run_greenhouse_daily_pipeline_full` |
| `t_etl_steps` | `etl._start_step()` / `etl._end_step()` |

### Parquet tracking (`public`)

| Table | Written by |
|-------|-----------|
| `ops_parquet_export_runs` | `jobs/parquet_export/export_features_dense.py` |
| `ops_parquet_export_state` | `jobs/parquet_export/export_features_dense.py` |

---

## 10. Gaps & Notes

### `greenbrain-platform` is a mirror
`/opt/greenbrain-platform/apps/ml-worker` is byte-for-byte identical to `/opt/greenhouse/repo` (`diff -rq` returns no differences). No separate systemd units point to it. It appears to be a staging clone.

### Parquet export has no timer
`export_features_dense.py` is functional and `ops_parquet_export_state.last_success_run_at = 2026-03-21 17:50` confirms it ran recently, but **no systemd timer or active pg_cron job schedules it**. The script `run_daily_parquet_batches.sh` exists as the orchestrator but must be triggered manually. A timer should be added.

### `sync_local_artifacts.py` has no timer
`gh-sync-local-artifacts` bin exists but no timer. A drift between DO Spaces content and `model_artifact_registry_v1` is possible if this is not called after each train run.

### Inactive pg_cron jobs need cleanup
8 inactive pg_cron entries (`one_shot_*`, `greenhouse_daily_full`, old monitor jobs) should be removed to avoid confusion. They are all `active=false` but clutter `cron.job`.

### `ml_monitor` schema used by `gh-monitor`
`gh-monitor` queries `ml_monitor.v_model_status`, `ml_monitor.v_model_stale`, `ml_monitor.v_run_recent`, but the `ml_monitor` schema is not in `current-schema.sql`. It likely exists as a separate view layer on Supabase. Needs documentation.

### ETL window is evening-only
`ops_auto_run_after_raw_q5m` runs only 19:00–23:59 UTC (20:00–00:59 Rome time). If sales data arrives before evening, ETL will not run until the next window. Backup job `ops_maybe_run_daily_5m_10_12_rome` exists but is inactive.

### `planner_roll4_reset_nightly` is inactive
Defined in pg_cron at `5 1 * * *` but `active=false`. If nightly roll4 reset is needed, this should be re-enabled.

### External ingestion not in workspace
The process that populates `greenhouse_sales_raw` (gestionale/POS connector) is entirely outside this workspace. The ETL pipeline has no way to self-start if raw data never arrives.
