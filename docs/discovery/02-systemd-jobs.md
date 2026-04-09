# Systemd Jobs — Full Analysis
> Evidence-based. All unit files read from `/etc/systemd/system/gh-*.{service,timer}`.
> All scripts read from `/opt/greenhouse/repo/jobs/` and `/opt/greenhouse/bin/`.

---

## Summary Table

| Job Name | Timer Schedule (UTC) | Service File | Entry Script | Python Job | Output |
|----------|---------------------|--------------|--------------|-----------|--------|
| `gh-refresh-registry` | `00:45` daily | `gh-refresh-registry.service` | `gh-refresh-ml-diag` + `gh-refresh-registry` | `jobs/refresh_registry.py` | `ml_forecast.family_model_state_v1`, `ml_ops.pipeline_run_log_v1` |
| `gh-train-missing` | `01:10` daily | `gh-train-missing.service` | `run_train_missing.sh` | `jobs/train_missing_batches.py` | DO Spaces bundles, `ml_ops.family_run_log_v1` |
| `gh-predict-all` | `01:30` daily | `gh-predict-all.service` | `run_predict_all.sh` | `jobs/predict_all.py` | `public.greenhouse_forecast_results_v2` |
| `gh-parquet-export` | `21:35` local† | `gh-parquet-export.service` | `run_daily_parquet_batches.sh` | `jobs/parquet_export/export_features_dense.py` | Supabase Storage parquet files |
| `gh-train-biweekly-all` | Sun 1st+15th `02:00` | `gh-train-biweekly-all.service` | inline bash | `jobs/train_all_monitor.py` | DO Spaces bundles (ALL families) |
| `gh-train-quarterly` | Jan/Apr/Jul/Oct 1 `02:30` | `gh-train-quarterly.service` | inline bash | `jobs/train_all_monitor.py` | DO Spaces bundles (ALL families) |

> †`gh-parquet-export` uses `OnCalendar=*-*-* 21:35:00` which is server local time (CET/CEST). Confirmed last run: `Wed 2026-03-25 21:36:11 CET`.

---

## 1. gh-refresh-registry

### Timer
```
OnCalendar=*-*-* 00:45:00
Persistent=true
RandomizedDelaySec=180
```
**Last run:** Thu 2026-03-26 00:46:47 CET  
**Next run:** Fri 2026-03-27 00:46:42 CET

### Service
```ini
[Service]
Type=oneshot
User=gh / Group=gh
WorkingDirectory=/opt/greenhouse/repo
EnvironmentFile=/opt/greenhouse/.env
Environment=RUN_TRIGGER_SOURCE=systemd_timer
ExecStartPre=/opt/greenhouse/bin/gh-refresh-ml-diag
ExecStart=/opt/greenhouse/bin/gh-refresh-registry
Nice=10
```

### Execution Chain

```
ExecStartPre: gh-refresh-ml-diag
  └─ psql → REFRESH MATERIALIZED VIEW (9 MVs in ml_diag):
       mv_family_day_base
       mv_family_stats
       mv_family_seasonality
       mv_family_intermittency
       mv_family_importance
       mv_family_metrics_v3
       mv_family_metrics_v3b
       mv_family_metrics_v4
       mv_family_metrics_v5

ExecStart: gh-refresh-registry → python3 -u jobs/refresh_registry.py
  └─ INSERT into ml_ops.pipeline_run_log_v1 (status=running)
  └─ SELECT ml_forecast.log_classification_changes_v1()
  └─ SELECT ml_forecast.sync_family_model_state_from_registry_v1()
  └─ SELECT ml_forecast.sync_family_model_state_from_artifacts_v1()
  └─ UPDATE ml_forecast.family_model_state_v1 SET needs_predict=true (ALL families)
  └─ UPDATE ml_ops.pipeline_run_log_v1 (status=success/failed)
```

### Dependencies
| Direction | Dependency |
|-----------|-----------|
| Upstream | `network-online.target` (systemd ordering only) |
| Data in | `ml_diag.mv_family_*` materialized views (refreshed in PreExec) |
| Data in | `ml_forecast.model_artifact_registry_v1` (read by `sync_from_artifacts`) |
| Data out | `ml_forecast.family_model_state_v1` — state flags updated |
| Data out | `ml_ops.classification_change_log_v1` — classification diffs |
| Data out | `ml_ops.pipeline_run_log_v1` — run log entry |
| Downstream | `gh-train-missing` runs 25 min later and reads `family_model_state_v1` |

### ML Worker File Correlation
| Service step | ML Worker file |
|-------------|---------------|
| `ExecStartPre: gh-refresh-ml-diag` | N/A — raw `psql` command, no Python file |
| `ExecStart: gh-refresh-registry` → `jobs/refresh_registry.py` | `/opt/greenhouse/repo/jobs/refresh_registry.py` |
| Called DB functions | Defined in `/opt/greenbrain-v2/database/current-schema.sql` (`ml_forecast` schema) |

---

## 2. gh-train-missing

### Timer
```
OnCalendar=*-*-* 01:10:00
Persistent=true
RandomizedDelaySec=120
```
**Last run:** Thu 2026-03-26 01:10:40 CET  
**Next run:** Fri 2026-03-27 01:10:44 CET

### Service
```ini
[Service]
Type=oneshot
User=gh / Group=gh
WorkingDirectory=/opt/greenhouse/repo
EnvironmentFile=/opt/greenhouse/.env
ExecStart=/opt/greenhouse/repo/jobs/run_train_missing.sh
ExecStartPost=/opt/greenhouse/bin/gh-sync-local-artifacts
Nice=10
```

### Execution Chain

```
ExecStart: run_train_missing.sh
  ├─ flock -n /opt/greenhouse/tmp/train_missing.lock  (exits if already running)
  ├─ source venv + .env
  ├─ python jobs/train_missing_batches.py
  │    ├─ check_job_enabled("train_missing") via ml_ops.job_schedule_config_v1
  │    ├─ INSERT ml_ops.pipeline_run_log_v1 (status=running)
  │    ├─ SELECT ml_forecast.v_family_execution_routing_v2
  │    │    WHERE needs_initial_train=true OR needs_retrain=true
  │    │    ORDER BY family_name  (up to TRAIN_LIMIT, default=all)
  │    ├─ For each batch of TRAIN_BATCH_SIZE=10:
  │    │    ├─ INSERT ml_ops.family_run_log_v1 (status=running)
  │    │    ├─ subprocess: python jobs/train_family_router.py --family <name>
  │    │    │    └─ routes to engine (LightGBM Tweedie / ETS / Croston / TSB / SARIMA / NAIVE_ZERO)
  │    │    │         └─ reads greenhouse_forecast_features_dense (parquet-first if PARQUET_ENABLE=1)
  │    │    │         └─ saves models_v4/bundle_<slug>_v4.pkl
  │    │    ├─ ensure_model_bundle.upload_bundle(slug) → DO Spaces models_v4/bundle_<slug>_v4.pkl
  │    │    ├─ mark_train_success/failed via ml_ops_bridge
  │    │    └─ UPDATE ml_ops.family_run_log_v1 (status=success/failed)
  │    └─ UPDATE ml_ops.pipeline_run_log_v1 (status=success/failed)
  └─ log: /opt/greenhouse/logs/train_missing_<stamp>.log
         symlink: train_missing_latest.log

ExecStartPost: gh-sync-local-artifacts → python3 -u jobs/sync_local_artifacts.py
  ├─ scan models_v4/bundle_*_v4.pkl on local filesystem
  ├─ for each bundle: UPSERT ml_forecast.model_artifact_registry_v1
  ├─ UPDATE ml_forecast.family_model_state_v1 (needs_initial_train=false where bundle found)
  └─ INSERT ml_ops.pipeline_run_log_v1
```

### Dependencies
| Direction | Dependency |
|-----------|-----------|
| Upstream | `gh-refresh-registry` ran 25 min earlier, setting `needs_retrain/needs_initial_train` |
| Data in | `ml_forecast.v_family_execution_routing_v2` (families needing train) |
| Data in | `ml_ops.job_schedule_config_v1` (`train_missing` must be enabled) |
| Data in | `greenhouse_forecast_features_dense` (or parquet cache on Supabase Storage) |
| Data out | `models_v4/bundle_<slug>_v4.pkl` (local filesystem) |
| Data out | DO Spaces `models_v4/bundle_<slug>_v4.pkl` |
| Data out | `ml_ops.family_run_log_v1`, `ml_ops.pipeline_run_log_v1` |
| Data out | `ml_forecast.family_model_state_v1` (train success/failed flags) |
| Data out | `ml_forecast.model_artifact_registry_v1` (post-step sync) |
| Downstream | `gh-predict-all` runs 20 min later; will skip families still missing bundles unless `AUTO_TRAIN_MISSING=1` |

### ML Worker File Correlation
| Service step | ML Worker file |
|-------------|---------------|
| `run_train_missing.sh` | `/opt/greenhouse/repo/jobs/run_train_missing.sh` |
| `jobs/train_missing_batches.py` | `/opt/greenhouse/repo/jobs/train_missing_batches.py` |
| subprocess `train_family_router.py` | `/opt/greenhouse/repo/jobs/train_family_router.py` |
| routes to engine | `/opt/greenhouse/repo/jobs/engines/engine_*.py` (6 engines) |
| single-family train | `/opt/greenhouse/repo/train_v4_single_family_tweedie.py` (for LightGBM engine) |
| `upload_bundle` | `/opt/greenhouse/repo/jobs/ensure_model_bundle.py` |
| `ml_ops_bridge` | `/opt/greenhouse/repo/jobs/ml_ops_bridge.py` |
| post: `sync_local_artifacts.py` | `/opt/greenhouse/repo/jobs/sync_local_artifacts.py` |

---

## 3. gh-predict-all

### Timer
```
OnCalendar=*-*-* 01:30:00
Persistent=true
RandomizedDelaySec=120
```
**Last run:** Thu 2026-03-26 01:32:12 CET  
**Next run:** Fri 2026-03-27 01:30:02 CET

### Service
```ini
[Service]
Type=oneshot
User=gh / Group=gh
WorkingDirectory=/opt/greenhouse/repo
EnvironmentFile=/opt/greenhouse/.env
ExecStart=/opt/greenhouse/repo/jobs/run_predict_all.sh
Nice=10
```

### Execution Chain

```
ExecStart: run_predict_all.sh
  ├─ flock -n /opt/greenhouse/tmp/predict_all.lock  (exits if already running)
  ├─ source venv + .env
  ├─ export RUN_TRIGGER_SOURCE=${RUN_TRIGGER_SOURCE:-systemd_timer}
  ├─ export GIT_SHA=$(git rev-parse --short HEAD)
  │
  ├─ [PRIORS STEP] psql → SELECT famiglia_slug FROM public.famiglie_catalog_static → /tmp/slugs_all.txt
  ├─ python3 tools/build_seasonal_priors.py --slugs-file /tmp/slugs_all.txt
  │    └─ reads greenhouse_forecast_features_dense (or parquet cache)
  │    └─ computes day-of-year demand profiles for all slugs
  │    └─ writes priors_cache/priors_v1.parquet
  ├─ python3 jobs/upload_priors_to_supabase.py
  │    └─ uploads priors_cache/priors_v1.parquet → Supabase Storage ml-snapshots/priors/priors_v1.parquet
  ├─ python3 jobs/download_priors_from_supabase.py
  │    └─ re-downloads priors from Storage (ensures predict reads same artifact as future workers)
  │
  └─ python jobs/predict_all.py
       ├─ check_job_enabled("predict_all") via ml_ops.job_schedule_config_v1
       ├─ INSERT ml_ops.pipeline_run_log_v1 (status=running)
       ├─ SELECT ml_forecast.v_family_execution_routing_v2 (all active families)
       ├─ For each family:
       │    ├─ INSERT ml_ops.family_run_log_v1 (status=running)
       │    ├─ ensure_bundle_any_engine(slug) — download from DO Spaces if missing locally
       │    │    └─ if missing & AUTO_TRAIN_MISSING=1: run train_family_router.py first
       │    ├─ subprocess: python jobs/predict_family_router.py --family <name>
       │    │    └─ routes to predict_<engine>.py
       │    │         └─ loads bundle_<slug>_v4.pkl
       │    │         └─ reads greenhouse_forecast_features_dense (parquet-first)
       │    │         └─ reads priors_cache/priors_v1.parquet
       │    │         └─ UPSERT public.greenhouse_forecast_results_v2
       │    ├─ mark_predict_success/failed via ml_ops_bridge
       │    └─ UPDATE ml_ops.family_run_log_v1 (status=success/failed)
       └─ UPDATE ml_ops.pipeline_run_log_v1 (status=success/failed)

  log: /opt/greenhouse/logs/predict_all_<stamp>.log
       symlink: predict_all_latest.log
       priors log: /opt/greenhouse/logs/build_priors_latest.log
```

### Dependencies
| Direction | Dependency |
|-----------|-----------|
| Upstream | `gh-train-missing` ran 20 min earlier (01:10), should have filled missing bundles |
| Data in | `ml_forecast.v_family_execution_routing_v2` (all active families) |
| Data in | `ml_ops.job_schedule_config_v1` (`predict_all` must be enabled) |
| Data in | `public.famiglie_catalog_static` (slug list for priors build) |
| Data in | `public.greenhouse_forecast_features_dense` (training history for priors + predict) |
| Data in | DO Spaces `models_v4/bundle_<slug>_v4.pkl` (model artifacts) |
| Data out | `public.greenhouse_forecast_results_v2` (forecast rows, ~90 days ahead per family+fascia) |
| Data out | Supabase Storage `ml-snapshots/priors/priors_v1.parquet` |
| Data out | `ml_ops.family_run_log_v1`, `ml_ops.pipeline_run_log_v1` |
| Data out | `ml_forecast.family_model_state_v1` (predict_last_at, needs_predict=false) |
| Downstream | Frontend reads `greenhouse_forecast_results_v2` via `/api/v1/forecast/series` |

### ML Worker File Correlation
| Service step | ML Worker file |
|-------------|---------------|
| `run_predict_all.sh` | `/opt/greenhouse/repo/jobs/run_predict_all.sh` |
| `tools/build_seasonal_priors.py` | `/opt/greenhouse/repo/tools/build_seasonal_priors.py` |
| `jobs/upload_priors_to_supabase.py` | `/opt/greenhouse/repo/jobs/upload_priors_to_supabase.py` |
| `jobs/download_priors_from_supabase.py` | `/opt/greenhouse/repo/jobs/download_priors_from_supabase.py` |
| `jobs/predict_all.py` | `/opt/greenhouse/repo/jobs/predict_all.py` |
| subprocess `predict_family_router.py` | `/opt/greenhouse/repo/jobs/predict_family_router.py` |
| routes to engine | `/opt/greenhouse/repo/jobs/engines/engine_*.py` |
| single-family predict | `/opt/greenhouse/repo/predict_v4_single_family_tweedie.py` (for LightGBM engine) |
| `ensure_bundle_any_engine` | `/opt/greenhouse/repo/jobs/ensure_model_bundle.py` |
| `ml_ops_bridge` | `/opt/greenhouse/repo/jobs/ml_ops_bridge.py` |

---

## 4. gh-parquet-export

### Timer
```
OnCalendar=*-*-* 21:35:00    ← server LOCAL time (CET/CEST)
Persistent=true
RandomizedDelaySec=120
```
**Last run:** Wed 2026-03-25 21:36:11 CET  
**Next run:** Thu 2026-03-26 21:36:48 CET

### Service
```ini
[Service]
Type=oneshot
User=gh / Group=gh
WorkingDirectory=/opt/greenhouse/repo/jobs/parquet_export
EnvironmentFile=/opt/greenhouse/.env
Environment=GB_ENV_FILE=/opt/greenhouse/.env
ExecStartPre=/opt/greenhouse/repo/jobs/parquet_export/check_etl_ready.sh
ExecStart=/bin/bash -lc '/opt/greenhouse/repo/jobs/parquet_export/scripts/run_daily_parquet_batches.sh'
TimeoutStartSec=0
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=6
```

### Execution Chain

```
ExecStartPre: check_etl_ready.sh
  └─ psql query:
       SELECT CASE
         WHEN etl.t_etl_runs.pipeline='greenhouse_daily_full'
              AND status='success'
              AND target_last = MAX(greenhouse_sales_raw.data_movimento)::date
              AND started_at >= now() - interval '12 hours'
         THEN 'READY' ELSE 'NOT_READY'
       END
  └─ exits 0 (READY) or non-zero (NOT_READY — service aborts without error)
  ── guards against exporting stale data if ETL hasn't run today

ExecStart: run_daily_parquet_batches.sh
  ├─ mkdir lock: /tmp/greenhouse_daily_parquet.lockdir  (exits if already running)
  ├─ unset FULL_EXPORT, ONLY_YEAR, ONLY_FAMILY_SLUG
  ├─ export BATCH_SIZE=50
  ├─ For each OFFSET in [0, 50, 100, ..., 800]  (17 batches, up to 850 families):
  │    ├─ export BATCH_OFFSET=$off
  │    ├─ retry loop (up to MAX_RETRIES=4, sleep 20s between):
  │    │    └─ python -u export_features_dense.py
  │    │         ├─ SELECT famiglia_slug, year from greenhouse_forecast_features_dense
  │    │         │    LIMIT BATCH_SIZE OFFSET BATCH_OFFSET
  │    │         ├─ for each (slug, year): query full year's rows
  │    │         ├─ write to parquet (pyarrow)
  │    │         ├─ upload to Supabase Storage:
  │    │         │    ml-snapshots/features_dense/v1/year=YYYY/famiglia_slug=<slug>/part.parquet
  │    │         ├─ UPSERT public.ops_parquet_export_state (per slug+year)
  │    │         └─ INSERT public.ops_parquet_export_runs (run log)
  │    └─ logs: logs/parquet_export/daily_<ts>_batch_<off>_try<N>.log
  └─ master log: /opt/greenhouse/logs/parquet_export/daily_<ts>.log
```

### Dependencies
| Direction | Dependency |
|-----------|-----------|
| Upstream | pg_cron `ops_auto_run_after_raw_q5m` must have completed ETL successfully today (guard via `check_etl_ready.sh`) |
| Data in | `public.greenhouse_forecast_features_dense` (all rows, up to 850 families × all years) |
| Data in | `public.ops_parquet_export_state` (tracks last successful export per slug+year) |
| Data out | Supabase Storage `ml-snapshots/features_dense/v1/year=Y/famiglia_slug=S/part.parquet` |
| Data out | `public.ops_parquet_export_runs` (run log per batch) |
| Data out | `public.ops_parquet_export_state` (last success per slug+year) |
| Downstream | `data_access_v1.py` reads these parquet files during train/predict (when `PARQUET_ENABLE=1`) |

### Timing Note
This job runs at **21:35 local** (after ETL which runs at ~20:00–22:00 local via pg_cron `*/5 19-23 *`). The `check_etl_ready.sh` guard ensures the export only proceeds if ETL finished within the last 12 hours. If ETL hasn't run, the service exits cleanly via pre-exec failure — `Persistent=true` means it will retry next calendar trigger.

### ML Worker File Correlation
| Service step | ML Worker file |
|-------------|---------------|
| `check_etl_ready.sh` | `/opt/greenhouse/repo/jobs/parquet_export/check_etl_ready.sh` |
| `run_daily_parquet_batches.sh` | `/opt/greenhouse/repo/jobs/parquet_export/scripts/run_daily_parquet_batches.sh` |
| `export_features_dense.py` | `/opt/greenhouse/repo/jobs/parquet_export/export_features_dense.py` |
| parquet reader (downstream) | `/opt/greenhouse/repo/data_access_v1.py` — `load_family_df_parquet_or_db()` |

---

## 5. gh-train-biweekly-all

### Timer
```
OnCalendar=Sun *-*-01,15 02:00:00   ← Sundays falling on 1st or 15th of month
Persistent=true
RandomizedDelaySec=300
```
**Last run:** Sun 2026-03-15 02:04:40 CET  
**Next run:** Sun 2026-11-01 02:00:16 CET *(next Sun that is 1st or 15th)*

### Service
```ini
[Service]
Type=oneshot
User=gh / Group=gh
WorkingDirectory=/opt/greenhouse/repo
EnvironmentFile=/opt/greenhouse/.env
ExecStart=/bin/bash -lc 'source /opt/greenhouse/venv/bin/activate \
    && export RUN_TRIGGER_SOURCE=systemd_timer \
    && python3 -u jobs/train_all_monitor.py'
TimeoutStartSec=0
ExecStartPost=/opt/greenhouse/bin/gh-sync-local-artifacts
Nice=10
```

### Execution Chain

```
ExecStart: inline bash
  ├─ source venv
  ├─ export RUN_TRIGGER_SOURCE=systemd_timer
  └─ python3 -u jobs/train_all_monitor.py
       ├─ check_job_enabled("train_biweekly_all") via ml_ops.job_schedule_config_v1
       ├─ INSERT ml_ops.pipeline_run_log_v1 (status=running)
       ├─ SELECT ml_forecast.v_family_execution_routing_v2
       │    WHERE is_active=true  (ALL active families, no needs_retrain filter)
       ├─ parallel subprocess pool (TRAIN_ALL_JOBS=4 workers):
       │    └─ for each family: jobs/train_family_router.py --family <name>
       │         └─ (same engine routing as train_missing)
       │         └─ reads greenhouse_forecast_features_dense (parquet-first)
       │         └─ saves models_v4/bundle_<slug>_v4.pkl
       └─ UPDATE ml_ops.pipeline_run_log_v1 (status=success/failed)
       Note: does NOT call upload_bundle inline — that happens via post-step

ExecStartPost: gh-sync-local-artifacts → python3 -u jobs/sync_local_artifacts.py
  └─ scan models_v4/bundle_*_v4.pkl
  └─ UPSERT ml_forecast.model_artifact_registry_v1
  └─ UPDATE ml_forecast.family_model_state_v1
```

### Key Difference vs gh-train-missing
| Aspect | gh-train-missing (daily) | gh-train-biweekly-all |
|--------|--------------------------|----------------------|
| Family scope | Only families where `needs_initial_train=true OR needs_retrain=true` | **ALL** active families unconditionally |
| Frequency | Every day | Every ~2 weeks (Sundays on 1st/15th) |
| Parallelism | Serial batches of 10 | 4 parallel workers |
| GIT_SHA | Set in run script | Not set (uses env default) |
| Use case | Fill gaps daily | Periodic full refresh |

### Dependencies
| Direction | Dependency |
|-----------|-----------|
| Upstream | No hard dependency on other gh-* jobs (runs at 02:00, after daily train/predict cycle) |
| Data in | `ml_forecast.v_family_execution_routing_v2` (ALL active families) |
| Data in | `ml_ops.job_schedule_config_v1` |
| Data in | `greenhouse_forecast_features_dense` (parquet-first via Supabase Storage) |
| Data out | `models_v4/bundle_<slug>_v4.pkl` (local + DO Spaces via post-step) |
| Data out | `ml_ops.pipeline_run_log_v1` |
| Data out | `ml_forecast.model_artifact_registry_v1`, `ml_forecast.family_model_state_v1` |

### ML Worker File Correlation
| Service step | ML Worker file |
|-------------|---------------|
| `jobs/train_all_monitor.py` | `/opt/greenhouse/repo/jobs/train_all_monitor.py` |
| subprocess `train_family_router.py` | `/opt/greenhouse/repo/jobs/train_family_router.py` |
| single-family train | `/opt/greenhouse/repo/train_v4_single_family_tweedie.py` + engine variants |
| post: `sync_local_artifacts.py` | `/opt/greenhouse/repo/jobs/sync_local_artifacts.py` |

---

## 6. gh-train-quarterly

### Timer
```
OnCalendar=*-01,04,07,10-01 02:30:00   ← Jan 1, Apr 1, Jul 1, Oct 1
Persistent=true
RandomizedDelaySec=900
```
**Last run:** Sun 2026-02-22 21:46:02 CET *(pre-dates April 1)*  
**Next run:** Wed 2026-04-01 02:30:40 CEST

### Service
```ini
[Service]
Type=oneshot
User=gh / Group=gh
WorkingDirectory=/opt/greenhouse/repo
EnvironmentFile=/opt/greenhouse/.env
ExecStart=/bin/bash -lc 'source /opt/greenhouse/venv/bin/activate \
    && export RUN_TRIGGER_SOURCE=systemd_timer \
    && export GIT_SHA="$(cd /opt/greenhouse/repo && git rev-parse --short HEAD 2>/dev/null || true)" \
    && python3 -u /opt/greenhouse/repo/jobs/train_all_monitor.py'
TimeoutStartSec=0
ExecStartPost=/opt/greenhouse/bin/gh-sync-local-artifacts
Nice=10
```

### Execution Chain
Identical to `gh-train-biweekly-all` except:
- **`GIT_SHA` is explicitly set** via `git rev-parse --short HEAD` before Python starts
- Runs on quarter boundaries rather than biweekly Sundays
- Both services invoke the **same Python file**: `jobs/train_all_monitor.py`

### Dependencies
Same as `gh-train-biweekly-all`. Additionally:
- `RandomizedDelaySec=900` (15 min jitter) avoids exact Jan/Apr/Jul/Oct 1 00:00 collision with other jobs

### ML Worker File Correlation
Identical to `gh-train-biweekly-all`.

---

## Daily Job Ordering (UTC)

```
00:45 ±3min   gh-refresh-registry
               ├─ REFRESH 9 ml_diag materialized views
               └─ sync family_model_state_v1 + set needs_predict=true

01:10 ±2min   gh-train-missing
               └─ train families with needs_initial_train=true or needs_retrain=true
               └─ POST: sync_local_artifacts

01:30 ±2min   gh-predict-all
               ├─ build + upload + download priors
               └─ predict all active families → greenhouse_forecast_results_v2

21:35 ±2min   gh-parquet-export  (local time CET/CEST)
               ├─ PRE: guard — ETL must have run today
               └─ export features_dense → Supabase Storage parquet
```

**Biweekly / Quarterly (independent of daily cycle):**
```
Sun *-*-01,15  02:00 ±5min   gh-train-biweekly-all
*-01,04,07,10-01 02:30 ±15min  gh-train-quarterly
  (both run jobs/train_all_monitor.py — ALL families)
```

---

## Pre/Post Execution Summary

| Service | ExecStartPre | ExecStart | ExecStartPost |
|---------|-------------|-----------|---------------|
| `gh-refresh-registry` | `gh-refresh-ml-diag` (psql REFRESH 9 MVs) | `gh-refresh-registry` → `refresh_registry.py` | — |
| `gh-train-missing` | — | `run_train_missing.sh` → `train_missing_batches.py` | `gh-sync-local-artifacts` → `sync_local_artifacts.py` |
| `gh-predict-all` | — | `run_predict_all.sh` → priors → `predict_all.py` | — |
| `gh-parquet-export` | `check_etl_ready.sh` (ETL guard) | `run_daily_parquet_batches.sh` → `export_features_dense.py` | — |
| `gh-train-biweekly-all` | — | inline bash → `train_all_monitor.py` | `gh-sync-local-artifacts` → `sync_local_artifacts.py` |
| `gh-train-quarterly` | — | inline bash + GIT_SHA → `train_all_monitor.py` | `gh-sync-local-artifacts` → `sync_local_artifacts.py` |

---

## Full ML Worker File → Service Mapping

| ML Worker File | Called by service | Role |
|----------------|------------------|------|
| `jobs/refresh_registry.py` | `gh-refresh-registry` (ExecStart) | Sync family model state from registry + artifacts |
| `jobs/train_missing_batches.py` | `gh-train-missing` (ExecStart) | Train only families with pending train flags |
| `jobs/train_all_monitor.py` | `gh-train-biweekly-all`, `gh-train-quarterly` (ExecStart) | Train ALL active families |
| `jobs/train_family_router.py` | `train_missing_batches.py`, `train_all_monitor.py` (subprocess) | Route family to correct engine |
| `train_v4_single_family_tweedie.py` | `train_family_router.py` (subprocess, LightGBM path) | Train LightGBM Tweedie model |
| `jobs/engines/engine_ets.py` | `train_family_router.py` (subprocess, ETS path) | Train ETS model |
| `jobs/engines/engine_croston.py` | `train_family_router.py` (subprocess) | Train Croston SBA |
| `jobs/engines/engine_tsb.py` | `train_family_router.py` (subprocess) | Train TSB |
| `jobs/engines/engine_sarima.py` | `train_family_router.py` (subprocess) | Train SARIMA |
| `jobs/engines/engine_naive_zero.py` | `train_family_router.py` (subprocess) | Naive zero baseline |
| `jobs/predict_all.py` | `gh-predict-all` (ExecStart via `run_predict_all.sh`) | Predict all active families |
| `jobs/predict_family_router.py` | `predict_all.py` (subprocess) | Route family to correct predict engine |
| `predict_v4_single_family_tweedie.py` | `predict_family_router.py` (subprocess, LightGBM) | Predict LightGBM |
| `tools/build_seasonal_priors.py` | `gh-predict-all` (via `run_predict_all.sh` step 2) | Build priors_v1.parquet |
| `jobs/upload_priors_to_supabase.py` | `gh-predict-all` (via `run_predict_all.sh` step 3) | Upload priors to Storage |
| `jobs/download_priors_from_supabase.py` | `gh-predict-all` (via `run_predict_all.sh` step 4) | Download priors from Storage |
| `jobs/ensure_model_bundle.py` | `predict_all.py`, `train_missing_batches.py` | Download/upload .pkl from DO Spaces |
| `jobs/ml_ops_bridge.py` | All orchestrator jobs | Write to `ml_ops.pipeline_run_log_v1`, `family_run_log_v1` |
| `jobs/sync_local_artifacts.py` | `gh-train-missing`, `gh-train-biweekly-all`, `gh-train-quarterly` (ExecStartPost) | Sync local bundles → `model_artifact_registry_v1` |
| `jobs/family_resolver.py` | `predict_all.py`, `train_missing_batches.py` | Resolve slug from family name |
| `jobs/parquet_export/export_features_dense.py` | `gh-parquet-export` (ExecStart via `run_daily_parquet_batches.sh`) | Export features_dense → Supabase Storage parquet |
| `data_access_v1.py` | All train + predict jobs (import) | Parquet-first data loader |

---

## Files NOT triggered by any service

| ML Worker File | How triggered | Notes |
|----------------|--------------|-------|
| `jobs/model_control.py` | Manual (`gh-*` bin / direct) | Governance CLI — assign models to families |
| `jobs/update_family_state.py` | Manual | Repair tool — mark train/predict success/failed |
| `jobs/benchmark_family.py` | Manual | Benchmark models; `job_schedule_config_v1: benchmark_weekly=disabled` |
| `jobs/validate_engines.py` | Manual / CI | End-to-end engine validation |
| `jobs/diagnose_families.py` | Manual | Demand diagnostics report |
| `jobs/dump_families.py` | Manual | Utility — dump family list |
| `backfill_*.py` (4 files) | Manual | One-time or on-demand backfill |
| `patch_holidays_features_weekly.py` | Manual | Patch holiday flags |
| `refresh_weekday_strength.py` | Manual | Recompute weekday strength tables |
| `sync_holidays.py` | Manual | Sync public holidays from API |
| `tools/hurdle_report.py` | Manual | Analysis only |
| `evaluate_v4_forecast.py` | Manual | Forecast vs actuals comparison |
| `fetch_forecast_dataset*.py` (2 files) | Manual | **Legacy** CSV export, not production |
