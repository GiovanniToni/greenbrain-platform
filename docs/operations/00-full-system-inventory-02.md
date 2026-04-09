# Full System Inventory — Part 2 of 3
# Phases 4–6: Data Pipeline · Database Map · Environment Variables
> Generated: 2026-03-27. Evidence-based from SQL schema, Python code, .env files.

---

## 4. Data Pipeline Graph

Full reconstruction of the data flow from raw sales to forecast and planner output.

```
EXTERNAL SOURCES
      │
      ▼
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 1: RAW DATA (populated by external ETL / manual import)  │
├─────────────────────────────────────────────────────────────────┤
│  greenhouse_sales_raw          ← daily sales from gestionale    │
│  greenhouse_products_normalized← product catalog (normalized)   │
│  greenhouse_stock_raw_upload   ← stock levels                   │
│  greenhouse_weather_daily      ← weather API data               │
│  greenhouse_holidays           ← holiday calendar               │
│  dim_iso_day                   ← static ISO day calendar        │
│  famiglie_catalog_static       ← static family catalog          │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼  pg_cron: run_greenhouse_daily_pipeline_full(40,14,2)
                         [jobs 11, 30, 39 — every 5min at 10-11, every 1min otherwise]
                     │
┌────────────────────▼────────────────────────────────────────────┐
│  LAYER 2: ETL PROCESSING (SQL functions in public schema)        │
├─────────────────────────────────────────────────────────────────┤
│  greenhouse_sales_enriched (view)                               │
│    ← sales_raw JOIN products_normalized                         │
│                                                                  │
│  greenhouse_sales_family_daily_v2 (view)                        │
│    ← aggregated by date + famiglia + fascia_prezzo_iva_inc       │
│                                                                  │
│  greenhouse_sales_family_daily_fact (table) ← written by        │
│    refresh_dense_range_from_fact()                              │
│                                                                  │
│  greenhouse_series_list_fact (table) ← valid series catalog     │
│                                                                  │
│  greenhouse_sales_family_daily_dense (table)                    │
│    ← refresh_dense_range(start, end)                            │
│    ← fills zeros for all dates in all series                    │
│                                                                  │
│  greenhouse_forecast_features_dense (table) ← MAIN FEATURE TABLE│
│    ← refresh_forecast_features_dense_range(start, end)         │
│    ← adds weather, holidays, lags, moving averages              │
│    Written to: etl.t_etl_runs (status=success)                  │
└────────────────────┬────────────────────────────────────────────┘
                     │
          ┌──────────┴──────────────────────┐
          │                                  │
          ▼                                  ▼
┌─────────────────────┐      ┌───────────────────────────────────┐
│  LAYER 3: ANALYTICS  │      │  LAYER 3: PARQUET EXPORT          │
│  (SQL pipeline)      │      │  (systemd: 21:35 daily)           │
├─────────────────────┤      ├───────────────────────────────────┤
│ t_core_analytics__*  │      │ export_features_dense.py          │
│  (12 daily/monthly/  │      │  reads: greenhouse_forecast_       │
│  weekly/yearly       │      │           features_dense          │
│  tables × 4 dims)   │      │  writes: Supabase Storage          │
│                      │      │    ml-snapshots/features_dense/   │
│ t_dashboard_sales_*  │      │    v1/year=Y/famiglia_slug=S/     │
│  (4 tables)          │      │    part.parquet                   │
│                      │      │  writes: ops_parquet_export_runs  │
│ mv_core_analytics__* │      │          ops_parquet_export_state  │
│  (6 MVs)             │      └──────────────┬────────────────────┘
│                      │                     │
│ ml_diag.mv_* (9 MVs) │                     │ parquet files on Supabase Storage
│  refreshed by        │                     │
│  gh-refresh-ml-diag  │                     ▼
└─────────────────────┘      ┌───────────────────────────────────┐
                              │  LAYER 4: ML TRAINING             │
                              │  (systemd: 01:10 + biweekly + Q)  │
                              ├───────────────────────────────────┤
                              │  train_missing_batches.py          │
                              │  train_all_monitor.py              │
                              │    reads: parquet (Supabase Stor.) │
                              │           or DB fallback           │
                              │    reads: ml_forecast.v_family_    │
                              │           execution_routing_v2     │
                              │    subprocess:                     │
                              │    train_v4_single_family_tweedie  │
                              │      engines: croston, ets, sarima │
                              │               tsb, seasonal_croston│
                              │               naive_zero           │
                              │    writes: DO Spaces               │
                              │      models_v4/bundle_<slug>_v4.pkl│
                              │    writes: family_model_state_v1   │
                              │            model_artifact_registry │
                              │            family_run_log_v1       │
                              └──────────────┬────────────────────┘
                                             │
                                             ▼
                              ┌───────────────────────────────────┐
                              │  LAYER 5: ML PREDICTION           │
                              │  (systemd: 01:30 daily)           │
                              ├───────────────────────────────────┤
                              │  run_predict_all.sh               │
                              │    build_seasonal_priors.py        │
                              │      reads: famiglie_catalog_static│
                              │      writes: priors_v1.parquet     │
                              │      uploads to Supabase Storage   │
                              │    predict_all.py                  │
                              │      reads: famiglie_catalog_static│
                              │      reads: family_model_registry  │
                              │      subprocess:                   │
                              │      predict_v4_single_family_tweedie│
                              │        reads: parquet or DB        │
                              │        reads: priors_v1.parquet    │
                              │        reads: model bundle from    │
                              │               DO Spaces            │
                              │        writes: greenhouse_forecast_│
                              │                results_v2          │
                              │        writes: t_forecast_fam_daily│
                              │        writes: ml_ops.family_run_log│
                              └──────────────┬────────────────────┘
                                             │
                                             ▼
                              ┌───────────────────────────────────┐
                              │  LAYER 6: PLANNER                 │
                              │  (pg_cron: nightly)               │
                              ├───────────────────────────────────┤
                              │  core_planner__nightly_roll4_reset │
                              │    job 12: 01:05 daily            │
                              │  core_planner__nightly_roll4_tick(2)│
                              │    job 13: 12:00 daily            │
                              │    reads: greenhouse_forecast_     │
                              │            results_v2             │
                              │    reads: greenhouse_forecast_     │
                              │            features_dense          │
                              │    reads: famiglie_catalog_static  │
                              │    writes: t_core_planner__*       │
                              │      assortment_calendar          │
                              │      fact_weekly                  │
                              │      heat_cells                   │
                              │      space_budget                 │
                              │      density                      │
                              └──────────────┬────────────────────┘
                                             │
                                             ▼
                              ┌───────────────────────────────────┐
                              │  LAYER 7: API + FRONTEND          │
                              │  (Docker: gb_v2_backend :8002)    │
                              ├───────────────────────────────────┤
                              │  FastAPI routers:                 │
                              │  /api/v1/analytics  → t_core_analytics__* + MVs │
                              │  /api/v1/dashboard  → t_dashboard_sales_* + forecast │
                              │  /api/v1/forecast   → greenhouse_forecast_results_v2 │
                              │  /api/v1/catalog    → famiglie_catalog_static     │
                              │  /api/v1/sales      → greenhouse_sales_* views    │
                              │  /api/v1/planner    → t_core_planner__*           │
                              │  /api/v1/ops        → ml_ops.v_* views            │
                              │  /api/v1/system     → health/system info          │
                              │                                   │
                              │  Frontend:                        │
                              │  VITE_API_BASE_URL=:8002          │
                              │  Auth via Supabase (supabase-js)  │
                              └───────────────────────────────────┘
```

---

## 5. Database Map

Database: Supabase PostgreSQL (hosted, `aws-1-eu-west-1.pooler.supabase.com`).
Local Docker DB: `gb_v2_postgres:17` on port 5433 (for local dev/client stack — **separate DB**).

Schemas present in schema: `public`, `etl`, `ml_forecast`, `ml_ops`, `ml_diag`, `auth`, `storage`,
`realtime`, `extensions`, `graphql`.

---

### Schema: `public` — Raw Data Tables

| Table | Written by | Read by |
|-------|-----------|---------|
| `greenhouse_sales_raw` | External ETL (gestionale import) | `run_greenhouse_daily_pipeline_full`, analytics views |
| `greenhouse_products_normalized` | Product ETL | `greenhouse_sales_enriched` view, pipeline |
| `greenhouse_stock_raw_upload` | Stock ETL | `greenhouse_stock_enriched` view |
| `greenhouse_weather_daily` | Weather ETL | `refresh_forecast_features_dense_range` |
| `greenhouse_holidays` | `sync_holidays.py` (manual) | Feature engineering |
| `greenhouse_weekday_strength` | `refresh_weekday_strength.py` (manual) | Feature engineering |
| `greenhouse_weekday_strength_family` | `refresh_weekday_strength.py` | Feature engineering |
| `famiglie_catalog_static` | Manual / migration | `predict_all.py`, `train_missing_batches.py`, planner |
| `dim_iso_day` | Static migration | Feature engineering |
| `greenhouse_alerts` | Pipeline | Monitoring |
| `greenhouse_stock_raw_upload` | Stock ETL | `greenhouse_stock_enriched` |

---

### Schema: `public` — ETL Output Tables

| Table | Written by | Read by |
|-------|-----------|---------|
| `greenhouse_sales_family_daily_fact` | `refresh_dense_range_from_fact()` | `refresh_dense_range` |
| `greenhouse_series_list_fact` | Pipeline | ML worker (family routing) |
| `greenhouse_sales_family_daily_dense` | `refresh_dense_range()` | Feature engineering |
| `greenhouse_forecast_features_dense` | `refresh_forecast_features_dense_range()` | ML worker, parquet export |

---

### Schema: `public` — Analytics Tables (written by pipeline, read by FastAPI)

| Table group | Count | Dimensions | Read by |
|------------|-------|-----------|---------|
| `t_core_analytics__series_daily_*` | 4 (famiglia, fascia, categoria, fascia_prezzo) | daily | analytics API |
| `t_core_analytics__series_weekly_*` | 4 | weekly | analytics API |
| `t_core_analytics__series_monthly_*` | 4 | monthly | analytics API |
| `t_core_analytics__series_yearly_*` | 4 | yearly | analytics API |
| `t_core_analytics__breakdown_daily_*_fp` | 6 + 6 v2 | daily × category | analytics API |
| `t_core_analytics__breakdown_weekly_*_fp` | 6 + 6 v2 | weekly × category | analytics API |
| `t_core_analytics__breakdown_monthly_*_fp` | 6 + 6 v2 | monthly × category | analytics API |
| `t_core_analytics__breakdown_yearly_*_fp` | 6 + 6 v2 | yearly × category | analytics API |
| `t_core_analytics__seasonality_month` | 1 | monthly seasonality | analytics API |
| `t_analytics_backfill_state` | 1 | backfill tracking | analytics pipeline |

---

### Schema: `public` — Dashboard Tables

| Table | Written by | Read by |
|-------|-----------|---------|
| `t_dashboard_sales_daily` | Pipeline | FastAPI dashboard |
| `t_dashboard_sales_weekly` | Pipeline | FastAPI dashboard |
| `t_dashboard_sales_monthly` | Pipeline | FastAPI dashboard |
| `t_dashboard_sales_yearly` | Pipeline | FastAPI dashboard |

---

### Schema: `public` — Forecast Output Tables

| Table | Written by | Read by |
|-------|-----------|---------|
| `greenhouse_forecast_results_v2` | `predict_v4_single_family_tweedie.py` | FastAPI forecast + planner |
| `t_forecast_fam_daily` | `predict_v4_single_family_tweedie.py` | FastAPI dashboard |

---

### Schema: `public` — Planner Tables

| Table | Written by | Read by |
|-------|-----------|---------|
| `t_core_planner__fact_weekly` | `core_planner__nightly_roll4_tick()` | Planner API |
| `t_core_planner__heat_cells` | `core_planner__nightly_roll4_tick()` | Planner API |
| `t_core_planner__assortment_calendar` | `core_planner__nightly_roll4_tick()` | Planner API |
| `t_core_planner__space_budget` | Manual / planner | Planner API |
| `t_core_planner__density` | Planner functions | Planner API |
| `t_core_planner__potsize_profile` | Static data | Planner API |
| `t_core_planner__params_level` | Manual configuration | Planner API |
| `t_core_planner__orchestrator_state` | `core_planner__*` functions | Planner API |
| `t_core_planner__refresh_state` | `core_planner__*` functions | Planner API |

---

### Schema: `public` — Operations / Logging

| Table | Written by | Read by |
|-------|-----------|---------|
| `ops_parquet_export_runs` | `export_features_dense.py` | Monitoring |
| `ops_parquet_export_state` | `export_features_dense.py` | `check_etl_ready.sh` (last success day) |
| `t_ops_pipeline_monitor` | `ops_pipeline_monitor_snapshot()` (pg_cron job 28) | `v_ops_pipeline_monitor_latest` |

---

### Schema: `public` — Materialized Views (refreshed by `gh-refresh-ml-diag`)

| Materialized View | Refresh trigger | Purpose |
|-------------------|----------------|---------|
| `mv_core_analytics__catalog_entities` | `ops_refresh_pipeline_monitor_snapshot()` | Catalog cache |
| `mv_core_analytics__series_daily_famiglia` | Same | Analytics cache |
| `mv_core_analytics__series_daily_fascia` | Same | Analytics cache |
| `mv_core_analytics__series_daily_fascia_prezzo` | Same | Analytics cache |
| `mv_core_analytics__series_daily_categoria` | Same | Analytics cache |
| `mv_core_analytics__breakdown_daily_fascia_fp` | Same | Analytics cache |
| `mv_famiglie_catalog` | `ops_refresh_pipeline_monitor_snapshot()` | Family catalog cache |

---

### Schema: `etl`

| Table | Written by | Read by |
|-------|-----------|---------|
| `etl.t_etl_runs` | `run_greenhouse_daily_pipeline_full()` | `check_etl_ready.sh`, monitoring |
| `etl.t_etl_steps` | `run_greenhouse_daily_pipeline_full()` | Debugging |

---

### Schema: `ml_forecast`

| Table | Written by | Read by |
|-------|-----------|---------|
| `ml_forecast.family_model_registry_v1` | `refresh_registry.py` | `train_missing_batches.py`, routing |
| `ml_forecast.family_model_registry_v2` | `refresh_registry.py` | `predict_all.py`, routing |
| `ml_forecast.family_model_state_v1` | `train_v4_single_family_tweedie.py`, `update_family_state.py` | Routing views |
| `ml_forecast.model_artifact_registry_v1` | `ensure_model_bundle.py` | `sync_local_artifacts.py` |
| `ml_forecast.family_model_assignment_v1` | `model_control.py` | `v_family_execution_routing_v2` |
| `ml_forecast.family_model_assignment_log_v1` | `model_control.py` | Audit |
| `ml_forecast.family_model_benchmark_v1` | `benchmark_family.py` | `v_benchmark_*` views |
| `ml_forecast.family_benchmark_run_v1` | `benchmark_family.py` | Benchmark views |
| `ml_forecast.family_model_suggestion_benchmark_v1` | `benchmark_family.py` | Suggestions views |
| `ml_forecast.class_model_map_v1` | Static migration | Engine routing |
| `ml_forecast.model_catalog_v1` | Static migration | Engine routing |
| `ml_forecast.model_engine_map_v1` | Static migration | Engine routing |
| `ml_forecast.execution_engine_catalog_v1` | Static migration | Engine routing |

**Key views:**
- `ml_forecast.v_family_execution_routing_v2` — read by `train_all_monitor.py` (replaces `mv_famiglie_catalog`)
- `ml_forecast.v_train_missing_candidates_v1` — read by `train_missing_batches.py`
- `ml_forecast.v_family_model_registry_v1/v2` — read by `predict_all.py`

---

### Schema: `ml_ops`

| Table | Written by | Read by |
|-------|-----------|---------|
| `ml_ops.family_run_log_v1` | `ml_ops_bridge.py` (called by train/predict) | Monitoring views |
| `ml_ops.pipeline_run_log_v1` | `ml_ops_bridge.py` | Monitoring views |
| `ml_ops.classification_change_log_v1` | State management | Audit |
| `ml_ops.job_schedule_config_v1` | Manual configuration | Routing |

**Key views (all read by FastAPI `/api/v1/ops`):**
- `ml_ops.v_family_health_v1` — overall family health
- `ml_ops.v_forecast_freshness_v1` — forecast age per family
- `ml_ops.v_model_stale_v1` — models needing retraining
- `ml_ops.v_train_missing_candidates_v1` — families missing bundles
- `ml_ops.v_predict_daily_candidates_v1` — families needing prediction
- `ml_ops.v_daily_pipeline_summary_v1` — daily summary
- `ml_ops.v_registry_health_v1` — registry freshness
- `ml_ops.v_registry_summary_v1` — registry count by engine
- `ml_ops.v_state_summary_v1` — state distribution
- `ml_ops.v_train_biweekly_candidates_v1` — biweekly candidates
- `ml_ops.v_family_ops_status_v1` — combined ops status

---

### Schema: `ml_diag`

9 materialized views (refreshed by `gh-refresh-ml-diag`):

| MV | Purpose |
|----|---------|
| `ml_diag.mv_family_day_base` | Base family × day aggregation |
| `ml_diag.mv_family_stats` | Statistical summary per family |
| `ml_diag.mv_family_intermittency` | Intermittency metrics |
| `ml_diag.mv_family_seasonality` | Seasonality metrics |
| `ml_diag.mv_family_importance` | Feature importance |
| `ml_diag.mv_family_metrics_v3` | Model metrics v3 |
| `ml_diag.mv_family_metrics_v3b` | Model metrics v3b |
| `ml_diag.mv_family_metrics_v4` | Model metrics v4 |
| `ml_diag.mv_family_metrics_v5` | Model metrics v5 |

14 diagnostic views (`v_family_diagnostics_*` through v7.2_quater).

---

### Key SQL Functions (public schema)

| Function | Called by | Does |
|----------|----------|------|
| `run_greenhouse_daily_pipeline_full(horizon, rebuild_days, ver)` | pg_cron 11/30/39, manual | Master ETL orchestrator |
| `ops_maybe_run_daily_pipeline()` | pg_cron 29/37/38 | Gated ETL (checks if already ran today) |
| `refresh_dense_range(start, end)` | pipeline | Refreshes dense sales table |
| `refresh_dense_range_from_fact(start, end)` | pipeline | Builds fact from raw |
| `refresh_forecast_features_dense_range(start, end)` | pipeline | Builds feature table |
| `refresh_core_analytics_range(...)` | pipeline | Refreshes analytics tables |
| `refresh_dashboard_sales_range(start, end)` | pipeline | Refreshes dashboard tables |
| `core_planner__nightly_roll4_reset()` | pg_cron 12 | Resets planner rolling window |
| `core_planner__nightly_roll4_tick(n)` | pg_cron 13 | Advances planner |
| `ops_pipeline_monitor_snapshot()` | pg_cron 28 | Takes pipeline monitor snapshot |
| `ops_refresh_pipeline_monitor_snapshot()` | pg_cron 31/32/34/35 | Refreshes MVs |
| `slugify_family(text)` | Various | Stable slug from family name |

---

## 6. Environment Variables

### 6.1 Source Files

| File | Used by |
|------|---------|
| `/opt/greenhouse/.env` | Direct `EnvironmentFile` for gh-train-biweekly-all + gh-train-quarterly; also sourced manually |
| `/opt/greenbrain-platform/infra/env/base.env` | All services that use `load_env.sh` (predict, train-missing, parquet, refresh-registry) |
| `/opt/greenbrain-platform/infra/env/dev.env` | Overlays base.env when `APP_ENV=dev` |
| `/opt/greenbrain-platform/infra/env/client.env` | Overlays base.env when `APP_ENV=client` |
| `/opt/greenbrain-v2/deploy/.env` | Docker-compose environment for gb_v2_* containers |
| `/opt/greenbrain-v2/deploy/.env.client` | Docker-compose client variant |
| `/opt/greenbrain/frontend/.env` | Vite build env for production frontend container |

---

### 6.2 DB Variables

| Variable | Value (production) | Used by |
|----------|-------------------|---------|
| `PG_HOST` | `aws-1-eu-west-1.pooler.supabase.com` | All ML Python jobs, FastAPI (as `postgres_host`) |
| `PG_PORT` | `5432` | All ML Python jobs |
| `PG_DB` | `postgres` | All ML Python jobs |
| `PG_USER` | `postgres.xbyhmzrlycixxrfjggvn` | All ML Python jobs |
| `PG_PASSWORD` | (redacted) | All ML Python jobs |
| `PG_SSLMODE` | `require` | All ML Python jobs |
| `DATABASE_URL` | `postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:${PG_PORT}/${PG_DB}?sslmode=require` | `ml_ops_bridge.py` (required), `check_etl_ready.sh`, `run_predict_all.sh` (psql call) |
| `SUPABASE_DB_HOST` | same as `PG_HOST` | `export_features_dense.py` only (alias — divergence!) |
| `SUPABASE_DB_PORT` | `5432` | `export_features_dense.py` only |
| `SUPABASE_DB_NAME` | `postgres` | `export_features_dense.py` only |
| `SUPABASE_DB_USER` | same as `PG_USER` | `export_features_dense.py` only |
| `SUPABASE_DB_PASSWORD` | (redacted) | `export_features_dense.py` only |

**Docker-only DB variables (greenbrain-v2 stack):**

| Variable | Value (client) | Used by |
|----------|---------------|---------|
| `POSTGRES_HOST` | `postgres` (Docker service name) | `gb_v2_backend`, `gb_v2_ml` |
| `POSTGRES_PORT` | `5432` | Docker backend |
| `POSTGRES_DB` | `greenbrain` | Docker backend |
| `POSTGRES_USER` | `greenbrain` | Docker backend |
| `POSTGRES_PASSWORD` | (redacted) | Docker backend |
| `POSTGRES_SSLMODE` | `disable` | Docker backend |
| `POSTGRES_EXPOSE_PORT` | `5433` | Host port mapping |

> **Note:** Two separate databases: Supabase (production ML + data) and local Docker PostgreSQL 17
> (greenbrain-v2 dev/client stack). The Docker backend reads from the local `greenbrain` database.

---

### 6.3 Storage Variables

| Variable | Value (production) | Used by |
|----------|-------------------|---------|
| `STORAGE_BACKEND` | `supabase` (dev.env) / `local` (client.env) | `storage/backend.py` factory |
| `SUPABASE_URL` | `https://xbyhmzrlycixxrfjggvn.supabase.co` | `SupabaseStorageBackend`, `data_access_v1.py`, priors scripts, parquet export |
| `SUPABASE_SERVICE_ROLE_KEY` | (redacted) | Same as above |
| `SUPABASE_KEY` | (legacy alias for SUPABASE_SERVICE_ROLE_KEY) | `data_access_v1.py` only |
| `SUPABASE_BUCKET` | `ml-snapshots` | Storage clients for parquet + priors |
| `DO_SPACES_REGION` | `fra1` | `scripts/spaces_io.py` (model bundles) |
| `DO_SPACES_BUCKET` | `greenbrainmodels` | `scripts/spaces_io.py` |
| `DO_SPACES_KEY` | (redacted) | `scripts/spaces_io.py` |
| `DO_SPACES_SECRET` | (redacted) | `scripts/spaces_io.py` |
| `SPACES_PREFIX` | `models_v4` | Model bundle path prefix |
| `SPACES_BT_PREFIX` | `backtests_v4` | Backtest path prefix |
| `SPACES_BETA_PREFIX` | `betas_v4` | Beta path prefix |
| `LOCAL_STORAGE_ROOT` | `/opt/greenhouse/storage` (base.env) or `/opt/greenbrain/storage` (client.env) | `LocalStorageBackend` |
| `PARQUET_ENABLE` | `1` | `data_access_v1.py` (use parquet vs DB) |
| `PARQUET_FORCE` | `0` | `data_access_v1.py` (force re-download) |
| `PARQUET_CACHE_DIR` | `/opt/greenhouse/repo/parquet_cache` | `data_access_v1.py` local cache |
| `PARQUET_DATASET_PREFIX` | `parquet/features_dense/v1` | Path prefix in storage |

**S3-mode only (for `S3StorageBackend` — not used in production):**

| Variable | Used by |
|----------|---------|
| `S3_ENDPOINT` | `s3_backend.py` |
| `S3_REGION` | `s3_backend.py` |
| `S3_ACCESS_KEY` | `s3_backend.py` |
| `S3_SECRET_KEY` | `s3_backend.py` |
| `S3_BUCKET` | `s3_backend.py` |

---

### 6.4 ML Variables

| Variable | Default | Used by |
|----------|---------|---------|
| `FAMIGLIE_SOURCE_TABLE` | `public.famiglie_catalog_static` | `predict_all.py`, priors builder |
| `FAMIGLIE_COL` | `famiglia` | `predict_all.py` |
| `PREDICT_LIMIT` | `0` (no limit) | `predict_all.py` |
| `PREDICT_ONLY_FAMILY` | `` | `predict_all.py` (single-family debug) |
| `PREDICT_FAMILY_TIMEOUT_SEC` | `1800` | `predict_all.py` |
| `AUTO_TRAIN_MISSING` | `1` | `predict_all.py` (trigger train if missing) |
| `TRAIN_BATCH_SIZE` | `10` | `train_missing_batches.py`, `train_all_batches.py` |
| `TRAIN_LIMIT` | `0` (no limit) | `train_missing_batches.py` |
| `TRAIN_TIMEOUT_SEC` | `7200` | `train_missing_batches.py`, `predict_all.py` |
| `TRAIN_ALL_JOBS` | (unset) | `train_all_monitor.py` (parallel workers) |
| `GH_BASE_DIR` | `/opt/greenhouse` | Path references |
| `GH_REPO_DIR` | `/opt/greenhouse/repo` | `predict_all.py`, `train_missing_batches.py` |
| `GH_LOG_DIR` | `/opt/greenhouse/logs` | `predict_all.py`, `train_missing_batches.py` |
| `GH_TMP_DIR` | `/opt/greenhouse/tmp` | Lock files |
| `PRIORS_LOCAL_PATH` | `/opt/greenhouse/repo/priors_cache/priors_v1.parquet` | Priors scripts |
| `PRIORS_REMOTE_PATH` | `priors/priors_v1.parquet` | Priors scripts (storage key) |
| `V4_PRIOR_SMOOTH_DOY` | `7` | `build_seasonal_priors.py` |
| `V4_ENABLE_DOY_GATE` | `1` | `seasonality_gate.py` |
| `V4_DOY_GATE_MODE` | `soft` | `seasonality_gate.py` |
| `V4_DOY_SMOOTH` | `15` | `seasonality_gate.py` |
| `V4_DOY_SOFT_FLOOR` | `0.01` | `seasonality_gate.py` |
| `V4_DOY_SOFT_MULT` | `0.25` | `seasonality_gate.py` |
| `V4_DOY_HARD_FLOOR` | `0.003` | `seasonality_gate.py` |
| `V4_DOY_GATE_DEBUG` | `0` | Debug mode |
| `V4_ENABLE_HURDLE` | `1` | `predict_v4_single_family_tweedie.py` |
| `V4_HURDLE_P_FLOOR` | `0.10` | Hurdle model |
| `V4_HURDLE_P_CAP` | `0.97` | Hurdle model |
| `V4_HURDLE_P_POWER` | `1.8` | Hurdle model |
| `V4_HURDLE_DEBUG` | `0` | Debug mode |

---

### 6.5 Backend / App Variables

| Variable | Value | Used by |
|----------|-------|---------|
| `APP_ENV` | `dev` (systemd), `client-local` (Docker-client) | `load_env.sh`, FastAPI |
| `APP_NAME` | `GreenBrain Backend` | FastAPI |
| `BACKEND_PORT` | `8001` (dev) / `8001` (client) | docker-compose |
| `FRONTEND_PORT` | `8081` (dev) / `8081` (client) | docker-compose |
| `PGADMIN_PORT` | `5050` | docker-compose client |
| `PGADMIN_DEFAULT_EMAIL` | `admin@greenbrain.com` | pgadmin |

---

### 6.6 Frontend Variables

| Variable | Value (production) | Used by |
|----------|-------------------|---------|
| `VITE_SUPABASE_URL` | `https://xbyhmzrlycixxrfjggvn.supabase.co` | `integrations/supabase/client.ts` |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | (JWT) | `integrations/supabase/client.ts` |
| `VITE_API_BASE_URL` | `http://127.0.0.1:8002` | `apiClient.ts` → all data hooks |

---

### 6.7 Scheduler / Runtime Variables

| Variable | Used by |
|----------|---------|
| `RUN_TRIGGER_SOURCE` | `ml_ops_bridge.py` — records how the job was triggered (systemd_timer, manual, etc.) |
| `GIT_SHA` | `ml_ops_bridge.py` — records git SHA with run logs |
| `GB_ROOT` | `base.env` — base path alias |
| `GB_REPO` | `base.env` — repo path alias |
