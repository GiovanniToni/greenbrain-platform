# Greenbrain System Data Flow
> Evidence-based reconstruction of the full production pipeline.
> Sources: SQL schema (`current-schema.sql`), Python source, systemd unit files, pg_cron jobs.
> Generated: 2026-03-27.

---

## Pipeline overview

```
EXTERNAL SOURCES
      │ gestionale (POS), weather API, stock system
      ▼
[ Layer 1: RAW ]           greenhouse_sales_raw, products_normalized, weather_daily, ...
      │ pg_cron ETL functions
      ▼
[ Layer 2: ETL ]           greenhouse_sales_family_daily_fact, series_list_fact
      │ refresh_dense_range()
      ▼
[ Layer 3: DENSE ]         greenhouse_sales_family_daily_dense
      │ refresh_forecast_features_dense_range()
      ▼
[ Layer 4: FEATURES ]      greenhouse_forecast_features_dense
      │                              │
      │ pg_cron analytics functions  │ systemd gh-parquet-export (21:35 local)
      ▼                              ▼
[ Layer 5: ANALYTICS ]     [ Layer 6: PARQUET EXPORT ]
t_core_analytics__*           Supabase Storage
t_dashboard_sales_*           ml-snapshots/features_dense/v1/...
mv_core_analytics__*
      │                              │
      │                              ▼
      │                    [ Layer 7: ML TRAINING ]    DO Spaces model bundles
      │                              │
      │                              ▼
      │                    [ Layer 8: ML PREDICTION ]
      │                              │
      │                    greenhouse_forecast_results_v2
      │                    t_forecast_fam_daily
      │                              │
      │              ┌───────────────┘
      ▼              ▼
[ Layer 9: PLANNER ]       t_core_planner__*
      │
      ▼
[ Layer 10: API ]          FastAPI gb_v2_backend :8002
      │
      ▼
[ Layer 11: FRONTEND ]     React gb_v2_frontend :8083
```

---

## Layer 1: RAW

External data ingested into Supabase PostgreSQL by systems outside this codebase.

### Tables written

| Table | Writer | Frequency |
|-------|--------|-----------|
| `public.greenhouse_sales_raw` | External gestionale ETL | Daily (exact time unknown) |
| `public.greenhouse_products_normalized` | Product catalog ETL | On change |
| `public.greenhouse_stock_raw_upload` | Stock ETL | Daily/on demand |
| `public.greenhouse_weather_daily` | Weather API job | Daily |
| `public.greenhouse_holidays` | `sync_holidays.py` (manual) | On calendar update |
| `public.greenhouse_weekday_strength` | `refresh_weekday_strength.py` (manual) | On demand |
| `public.greenhouse_weekday_strength_family` | `refresh_weekday_strength.py` (manual) | On demand |
| `public.famiglie_catalog_static` | Manual SQL / migrations | On catalog change |
| `public.dim_iso_day` | Static SQL migration | One-time |

### Tables read by next layer

All tables above are read by `run_greenhouse_daily_pipeline_full()`.

### Storage involved

None. Raw data lives exclusively in Supabase PostgreSQL.

### Downstream dependency

Layer 2 (ETL) cannot produce correct output if:
- `greenhouse_sales_raw` has no data for today
- `greenhouse_products_normalized` is stale (joins fail or produce wrong family aggregations)
- `greenhouse_weather_daily` is missing dates (weather features will be NULL)
- `greenhouse_holidays` is missing (holiday flag features will be NULL)

---

## Layer 2: ETL

SQL pipeline orchestrated by `run_greenhouse_daily_pipeline_full()`. Triggered by pg_cron.

### SQL functions involved

| Function | Signature | Called by |
|----------|-----------|-----------|
| `run_greenhouse_daily_pipeline_full` | `(horizon int, rebuild_days int, ver int)` | pg_cron #11, #37(gated), #29(gated) |
| `ops_maybe_run_daily_pipeline` | `()` | pg_cron #37, #29 — checks `etl.t_etl_runs` before calling full pipeline |
| `refresh_dense_range_from_fact` | `(start date, end date)` | Called inside `run_greenhouse_daily_pipeline_full` |
| `refresh_dense_range` | `(start date, end date)` | Called inside `run_greenhouse_daily_pipeline_full` |

### Tables read

```
greenhouse_sales_raw
greenhouse_products_normalized
greenhouse_series_list_fact  (catalog of valid series)
famiglie_catalog_static
dim_iso_day
```

### Tables written

| Table | Written by | Purpose |
|-------|-----------|---------|
| `public.greenhouse_sales_family_daily_fact` | `refresh_dense_range_from_fact()` | Aggregated daily sales per family+price-bracket |
| `public.greenhouse_series_list_fact` | `refresh_dense_range_from_fact()` | Catalog of valid (family, fascia_prezzo) series |
| `public.etl.t_etl_runs` | `run_greenhouse_daily_pipeline_full()` | Run record with status, timestamps. **Gates parquet export.** |
| `public.etl.t_etl_steps` | `run_greenhouse_daily_pipeline_full()` | Step-level timing for debugging |

### pg_cron jobs involved

| jobid | Schedule (UTC) | Notes |
|-------|---------------|-------|
| #11 | `*/5 10-11 * * *` | Primary ungated trigger, morning window |
| #37 | `*/5 9-11 * * *` | Gated; skips if today already succeeded |
| #29 | `*/5 19-23 * * *` | Gated; evening catch-up for late data |
| ~~#30~~ | ~~`* * * * *`~~ | ⛔ disable — duplicate of #39 |
| ~~#39~~ | ~~`* * * * *`~~ | ⛔ disable — duplicate of #30 |

### Downstream dependency

Layer 3 cannot run correctly without fresh `greenhouse_sales_family_daily_fact`.
`etl.t_etl_runs` with `status=success` is the gate for `gh-parquet-export` (Layer 6).

---

## Layer 3: DENSE

Zero-filled daily sales series for every (family, fascia_prezzo, date) combination in the catalog.

### SQL functions involved

| Function | Signature | Called by |
|----------|-----------|---------|
| `refresh_dense_range` | `(start date, end date)` | `run_greenhouse_daily_pipeline_full` |

### Tables read

```
greenhouse_sales_family_daily_fact   (actual sales, may have gaps)
greenhouse_series_list_fact          (catalog of valid series)
dim_iso_day                          (calendar spine for zero-fill)
```

### Tables written

| Table | Purpose |
|-------|---------|
| `public.greenhouse_sales_family_daily_dense` | Complete gapless daily time series — every date has a row, zero on days with no sales |

### Storage involved

None. Entirely within Supabase PostgreSQL.

### Downstream dependency

`greenhouse_sales_family_daily_dense` is the input to feature engineering (Layer 4). A missing date range or stale data here propagates incorrect features to all ML models.

---

## Layer 4: FEATURES

Feature engineering. Joins dense sales with weather, holidays, weekday strength, lagged values, and moving averages to produce the ML input table.

### SQL functions involved

| Function | Signature | Called by |
|----------|-----------|---------|
| `refresh_forecast_features_dense_range` | `(start date, end date)` | `run_greenhouse_daily_pipeline_full` |

### Tables read

```
greenhouse_sales_family_daily_dense   (base sales series)
greenhouse_weather_daily              (temperature, precipitation)
greenhouse_holidays                   (holiday flags)
greenhouse_weekday_strength           (global weekday multipliers)
greenhouse_weekday_strength_family    (per-family weekday multipliers)
dim_iso_day                           (ISO week, DOY, month metadata)
famiglie_catalog_static               (family metadata)
```

### Tables written

| Table | Purpose |
|-------|---------|
| `public.greenhouse_forecast_features_dense` | **Primary ML input table.** Contains all features: sales lags, moving averages, weather, holiday flags, weekday weights, DOY, ISO week. One row per (family, fascia_prezzo, date). |

### Storage involved

None at this layer. The downstream `gh-parquet-export` job reads this table and writes to Supabase Storage.

### Downstream dependency

`greenhouse_forecast_features_dense` is the single most critical table in the system:
- Read by Layer 5 (analytics SQL functions)
- Read by Layer 6 (parquet export → ML training + prediction)
- Read by Layer 9 (planner function `core_planner__nightly_roll4_tick`)
- Read directly by `data_access_v1.py` when parquet is unavailable (DB fallback)

---

## Layer 5: ANALYTICS

Materialized summaries for the frontend analytics views. Populated by the same ETL pipeline that runs Layer 2–4.

### SQL functions involved

| Function | Called by |
|----------|-----------|
| `refresh_core_analytics_range(...)` | `run_greenhouse_daily_pipeline_full` |
| `refresh_dashboard_sales_range(start, end)` | `run_greenhouse_daily_pipeline_full` |
| `ops_refresh_pipeline_monitor_snapshot()` | pg_cron #31, #32, #34, #35 — refreshes MVs |

### Tables read

```
greenhouse_forecast_features_dense   (aggregation source)
greenhouse_sales_family_daily_dense  (raw aggregation)
greenhouse_forecast_results_v2       (for dashboard forecast summary)
famiglie_catalog_static              (dimension metadata)
```

### Tables written

**Core analytics tables (48+ total — 4 granularities × 4 dimension breakdowns × ~3 variants):**

| Group | Tables | Dimensions |
|-------|--------|-----------|
| `t_core_analytics__series_daily_*` | 4 | famiglia, fascia, categoria, fascia_prezzo |
| `t_core_analytics__series_weekly_*` | 4 | same 4 dims |
| `t_core_analytics__series_monthly_*` | 4 | same 4 dims |
| `t_core_analytics__series_yearly_*` | 4 | same 4 dims |
| `t_core_analytics__breakdown_daily_*_fp` | 6 + 6 v2 | daily × category breakdown |
| `t_core_analytics__breakdown_weekly_*_fp` | 6 + 6 v2 | weekly × category breakdown |
| `t_core_analytics__breakdown_monthly_*_fp` | 6 + 6 v2 | monthly × category breakdown |
| `t_core_analytics__breakdown_yearly_*_fp` | 6 + 6 v2 | yearly × category breakdown |
| `t_core_analytics__seasonality_month` | 1 | monthly seasonality index |
| `t_analytics_backfill_state` | 1 | backfill tracking |

**Dashboard tables:**

| Table | Purpose |
|-------|---------|
| `t_dashboard_sales_daily` | Daily sales summary |
| `t_dashboard_sales_weekly` | Weekly sales summary |
| `t_dashboard_sales_monthly` | Monthly sales summary |
| `t_dashboard_sales_yearly` | Yearly sales summary |

**Materialized views (refreshed by `ops_refresh_pipeline_monitor_snapshot()`):**

| MV | Purpose |
|----|---------|
| `mv_core_analytics__catalog_entities` | Catalog dimension cache |
| `mv_core_analytics__series_daily_famiglia` | Fast daily read by famiglia |
| `mv_core_analytics__series_daily_fascia` | Fast daily read by fascia |
| `mv_core_analytics__series_daily_fascia_prezzo` | Fast daily read by fascia_prezzo |
| `mv_core_analytics__series_daily_categoria` | Fast daily read by categoria |
| `mv_core_analytics__breakdown_daily_fascia_fp` | Fast breakdown read |
| `mv_famiglie_catalog` | Family catalog cache |

**ml_diag materialized views (refreshed by `gh-refresh-registry` ExecStartPre):**

| MV | Purpose |
|----|---------|
| `ml_diag.mv_family_day_base` | Base family × day aggregation |
| `ml_diag.mv_family_stats` | Statistical summary per family |
| `ml_diag.mv_family_intermittency` | Intermittency metrics |
| `ml_diag.mv_family_seasonality` | Seasonality metrics |
| `ml_diag.mv_family_importance` | Feature importance scores |
| `ml_diag.mv_family_metrics_v3/v3b/v4/v5` | 4 ML metric MVs |

### Systemd jobs involved

- **`gh-refresh-registry`** (00:45 local): refreshes `ml_diag.mv_*` (9 views) as ExecStartPre

### pg_cron jobs involved

| jobid | Schedule | Function |
|-------|---------|----------|
| #31 | `*/10 19-23 * * *` UTC | `ops_refresh_pipeline_monitor_snapshot()` |
| #32 | `*/2 10-12 * * *` UTC | `ops_refresh_pipeline_monitor_snapshot()` |
| #34 | `*/30 0-9,13-23 * * *` UTC | `ops_refresh_pipeline_monitor_snapshot()` |
| #35 | `*/5 9-11 * * *` UTC | `ops_refresh_pipeline_monitor_snapshot()` |

### Downstream dependency

All `t_core_analytics__*` and `t_dashboard_sales_*` tables are read directly by the FastAPI backend (Layer 10). MVs are read instead of base tables in high-frequency API calls for performance.

---

## Layer 6: PARQUET EXPORT

Converts `greenhouse_forecast_features_dense` into partitioned parquet files on Supabase Storage. This is the primary data format consumed by the ML worker.

### Systemd jobs involved

| Job | Schedule | Role |
|-----|----------|------|
| `gh-parquet-export` | 21:35 local daily | Orchestrates all batches |

### Shell scripts involved

| Script | Path | Role |
|--------|------|------|
| `check_etl_ready.sh` | `/opt/greenbrain-platform/apps/ml-worker/jobs/parquet_export/check_etl_ready.sh` | Pre-check: query `etl.t_etl_runs` |
| `run_daily_parquet_batches.sh` | `/opt/greenbrain-platform/apps/ml-worker/jobs/parquet_export/scripts/run_daily_parquet_batches.sh` | Runs 17 batch iterations (offset 0, 50, 100…800) |

### Python involved

| Script | Path (active) | Role |
|--------|--------------|------|
| `export_features_dense.py` | `/opt/greenhouse/repo/jobs/parquet_export/export_features_dense.py` | Reads DB batch, converts to parquet bytes, uploads to Supabase Storage |

### Tables read

```
public.greenhouse_forecast_features_dense   (batch-read by family_slug, batch_offset)
etl.t_etl_runs                              (pre-check only — must have today's success row)
```

### Tables written

| Table | Purpose |
|-------|---------|
| `public.ops_parquet_export_runs` | One row per batch run — start/end time, families processed, error count |
| `public.ops_parquet_export_state` | Latest success date per prefix — read by `check_etl_ready.sh` on next day |

### Storage written

```
Supabase Storage bucket: ml-snapshots
Path pattern: features_dense/v1/year={YYYY}/famiglia_slug={slug}/part.parquet

One file per (year, slug) combination.
Batch structure: 17 batches × 50 families × all years = ~850 family-year partitions per run.
```

### Env dependencies (unique to this layer)

`export_features_dense.py` reads `SUPABASE_DB_HOST/PORT/NAME/USER/PASSWORD` (not `PG_*`).
This is a divergence from every other ML job. See Layer 7 notes.

### Downstream dependency

Parquet files are the primary feature data source for Layers 7 and 8. If this job is skipped:
- Training (Layer 7) falls back to direct DB reads — significantly slower, higher DB load
- Prediction (Layer 8) falls back to direct DB reads — same
- No error is raised; fallback is silent. Stale parquet is used until refreshed.

---

## Layer 7: ML TRAINING

Trains per-family probabilistic forecasting models. Reads parquet (preferred) or DB (fallback). Writes model bundles to DO Spaces.

### Systemd jobs involved

| Job | Schedule | Scope |
|-----|----------|-------|
| `gh-train-missing` | 01:10 local daily | Families missing bundles only |
| `gh-train-biweekly-all` | Sun 1st+15th 02:00 local | All families |
| `gh-train-quarterly` | Jan/Apr/Jul/Oct 1st 02:30 local | All families |

### Python involved

| Script | Path (active) | Role |
|--------|--------------|------|
| `train_missing_batches.py` | `/opt/greenhouse/repo/jobs/train_missing_batches.py` | Orchestrator: reads candidate list, dispatches per-family training |
| `train_all_monitor.py` | `/opt/greenhouse/repo/jobs/train_all_monitor.py` | Biweekly/quarterly orchestrator: trains all families |
| `train_v4_single_family_tweedie.py` | `/opt/greenhouse/repo/train_v4_single_family_tweedie.py` | Per-family trainer subprocess |
| `ensure_model_bundle.py` | `/opt/greenhouse/repo/jobs/ensure_model_bundle.py` | Download existing bundle from DO Spaces before retraining (incremental) |
| `data_access_v1.py` | `/opt/greenhouse/repo/data_access_v1.py` | Feature loader: parquet-first with DB fallback |
| `sync_local_artifacts.py` | `/opt/greenhouse/repo/jobs/sync_local_artifacts.py` | Post-train: upload local bundles to DO Spaces (ExecStartPost) |
| ML engines (8 total) | `/opt/greenhouse/repo/jobs/engines/` | `engine_croston.py`, `engine_ets.py`, `engine_sarima.py`, `engine_tsb.py`, `engine_seasonal_croston.py`, `engine_naive_zero.py`, `engine_tweedie.py`, `engine_ensemble.py` |

### Tables read

| Table | Used by |
|-------|---------|
| `ml_forecast.v_train_missing_candidates_v1` | `train_missing_batches.py` — which families to train |
| `ml_forecast.v_family_execution_routing_v2` | `train_all_monitor.py` — all active families |
| `ml_forecast.family_model_registry_v1` | Engine routing — which engine per family |
| `ml_forecast.model_catalog_v1` | Static engine metadata |
| `ml_forecast.model_engine_map_v1` | Engine → class mapping |
| `public.greenhouse_forecast_features_dense` | DB fallback if parquet unavailable |

### Storage read

```
Supabase Storage (via data_access_v1.py):
  ml-snapshots/features_dense/v1/year={Y}/famiglia_slug={slug}/part.parquet
  → cached locally to: $PARQUET_CACHE_DIR (default: /opt/greenhouse/repo/parquet_cache/)

DO Spaces (via ensure_model_bundle.py):
  models_v4/bundle_{slug}_v4.pkl  → downloaded to /opt/greenhouse/repo/models_v4/
  (for incremental retraining — existing bundle loaded as warm start)
```

### Tables written

| Table | Written by | Purpose |
|-------|-----------|---------|
| `ml_forecast.family_model_state_v1` | `train_v4_single_family_tweedie.py` | Model version, last train date, metrics |
| `ml_forecast.model_artifact_registry_v1` | `ensure_model_bundle.py` | Bundle registration (path, checksum) |
| `ml_ops.family_run_log_v1` | `ml_ops_bridge.py` (called inside train) | Per-family execution log (start, end, error, metrics) |

### Storage written

```
DO Spaces bucket: greenbrainmodels
Path pattern: models_v4/bundle_{slug}_v4.pkl
  → one .pkl file per family slug (scikit-learn/statsmodels model bundle)

Local disk (intermediate):
  /opt/greenhouse/repo/models_v4/{slug}/  → sync'd to DO Spaces by ExecStartPost
```

### Downstream dependency

DO Spaces model bundles are the primary input to Layer 8 (ML Prediction). If a family's bundle is missing or corrupt, `predict_all.py` will:
1. Attempt inline training via `AUTO_TRAIN_MISSING=1` (if set)
2. Skip prediction for that family if training also fails
3. Leave stale forecast rows in `greenhouse_forecast_results_v2` from previous run

---

## Layer 8: ML PREDICTION

Runs daily predictions for all active families. Writes forecast results consumed by the planner and frontend.

### Systemd jobs involved

| Job | Schedule | Scope |
|-----|----------|-------|
| `gh-predict-all` | 01:30 local daily | All families in registry |

### Python involved

| Script | Path (active) | Role |
|--------|--------------|------|
| `run_predict_all.sh` | `/opt/greenbrain-platform/apps/ml-worker/jobs/run_predict_all.sh` | Entry script: builds priors, uploads/downloads, runs predict |
| `build_seasonal_priors.py` | `/opt/greenhouse/repo/tools/build_seasonal_priors.py` | Builds `priors_v1.parquet` from `famiglie_catalog_static` |
| `upload_priors_to_supabase.py` | `/opt/greenhouse/repo/jobs/upload_priors_to_supabase.py` | Uploads `priors_v1.parquet` to Supabase Storage |
| `download_priors_from_supabase.py` | `/opt/greenhouse/repo/jobs/download_priors_from_supabase.py` | Downloads `priors_v1.parquet` back to local disk |
| `predict_all.py` | `/opt/greenhouse/repo/jobs/predict_all.py` | Orchestrator: dispatches per-family prediction |
| `predict_v4_single_family_tweedie.py` | `/opt/greenhouse/repo/predict_v4_single_family_tweedie.py` | Per-family prediction subprocess |
| `data_access_v1.py` | `/opt/greenhouse/repo/data_access_v1.py` | Feature loader: parquet-first with DB fallback |
| `ensure_model_bundle.py` | `/opt/greenhouse/repo/jobs/ensure_model_bundle.py` | Download model bundle from DO Spaces |
| `seasonality_gate.py` | `/opt/greenhouse/repo/` | V4 DOY gate (softens seasonality signal near year-end) |
| `ml_ops_bridge.py` | `/opt/greenhouse/repo/` | Writes run logs to `ml_ops.*` tables |

### Tables read

| Table | Used by |
|-------|---------|
| `public.famiglie_catalog_static` | `predict_all.py` — active family list (psql query in shell script) |
| `ml_forecast.family_model_registry_v2` | `predict_all.py` — which families to predict and which engine |
| `ml_forecast.family_model_registry_v1` | Routing cross-reference |
| `public.greenhouse_forecast_features_dense` | DB fallback via `data_access_v1.py` |

### Storage read

```
Supabase Storage (via data_access_v1.py):
  ml-snapshots/features_dense/v1/year={Y}/famiglia_slug={slug}/part.parquet
  → cached locally to: $PARQUET_CACHE_DIR

Supabase Storage (via download_priors_from_supabase.py):
  priors/priors_v1.parquet
  → written locally to: $PRIORS_LOCAL_PATH (default: /opt/greenhouse/repo/priors_cache/priors_v1.parquet)

DO Spaces (via ensure_model_bundle.py):
  models_v4/bundle_{slug}_v4.pkl
  → downloaded to: /opt/greenhouse/repo/models_v4/
```

### Storage written

```
Supabase Storage (via upload_priors_to_supabase.py):
  priors/priors_v1.parquet  ← uploaded then immediately re-downloaded for consistency check
```

### Tables written

| Table | Written by | Purpose |
|-------|-----------|---------|
| `public.greenhouse_forecast_results_v2` | `predict_v4_single_family_tweedie.py` | **Primary forecast output.** Per-family, per-date, per-horizon probabilistic forecast. Read by planner + API. |
| `public.t_forecast_fam_daily` | `predict_v4_single_family_tweedie.py` | Simplified daily aggregate forecast. Read by dashboard API. |
| `ml_ops.family_run_log_v1` | `ml_ops_bridge.py` | Per-family run log (timing, success, error) |
| `ml_ops.pipeline_run_log_v1` | `ml_ops_bridge.py` | Pipeline-level log (total families, duration, `RUN_TRIGGER_SOURCE`, `GIT_SHA`) |

### Downstream dependency

`greenhouse_forecast_results_v2` feeds:
- **Layer 9 (Planner)** at 12:00 UTC — if predict finishes by then
- **Layer 10 (API)** `/api/v1/forecast` and `/api/v1/dashboard`
- **Layer 5 (Analytics)** refresh functions that join forecast data

---

## Layer 9: PLANNER

Computes the assortment planning output from forecast results. Runs as a SQL function via pg_cron.

### pg_cron jobs involved

| jobid | Schedule (UTC) | Function | Role |
|-------|---------------|----------|------|
| #12 | `5 1 * * *` | `core_planner__nightly_roll4_reset()` | Resets orchestrator state before tick |
| #13 | `0 12 * * *` | `core_planner__nightly_roll4_tick(2)` | Advances rolling 4-week window |

### SQL functions involved

| Function | Signature |
|----------|-----------|
| `core_planner__nightly_roll4_reset` | `()` |
| `core_planner__nightly_roll4_tick` | `(n int)` — `n=2` steps per run |

### Tables read

| Table | Used by |
|-------|---------|
| `public.greenhouse_forecast_results_v2` | `nightly_roll4_tick` — forecast horizon per family |
| `public.greenhouse_forecast_features_dense` | `nightly_roll4_tick` — recent actuals for context |
| `public.famiglie_catalog_static` | `nightly_roll4_tick` — family metadata |
| `t_core_planner__params_level` | Planning parameters (margins, targets) |
| `t_core_planner__space_budget` | Physical space constraints per level |
| `t_core_planner__potsize_profile` | Pot size distribution |
| `t_core_planner__orchestrator_state` | State machine (reset by #12) |
| `t_core_planner__refresh_state` | Refresh tracking |

### Tables written

| Table | Purpose |
|-------|---------|
| `t_core_planner__fact_weekly` | Weekly per-family assortment plan (units, revenue) |
| `t_core_planner__heat_cells` | Heatmap cells for assortment calendar view |
| `t_core_planner__assortment_calendar` | Calendar-format assortment events |
| `t_core_planner__density` | Density allocation per space/pot profile |
| `t_core_planner__orchestrator_state` | Updated state after tick |
| `t_core_planner__refresh_state` | Refresh timestamps |

### Downstream dependency

All `t_core_planner__*` output tables are read by Layer 10 (API) via the `/api/v1/planner` router.

---

## Layer 10: API

FastAPI backend serving all data to the frontend. Runs in Docker container `gb_v2_backend` on port 8002.

### Runtime

| Container | Image | Port | Source volume |
|-----------|-------|------|---------------|
| `gb_v2_backend` | python:3.11-slim | 8002 | `/opt/greenbrain-v2/backend:/app` |

### Entrypoint

`uvicorn app.main:app --host 0.0.0.0 --port 8000` (Docker-internal; host sees :8002)

### Routers and tables they read

| Router | Endpoint prefix | Primary tables read |
|--------|----------------|-------------------|
| `analytics` | `/api/v1/analytics` | `t_core_analytics__*`, `mv_core_analytics__*` |
| `dashboard` | `/api/v1/dashboard` | `t_dashboard_sales_*`, `greenhouse_forecast_results_v2`, `t_forecast_fam_daily` |
| `forecast` | `/api/v1/forecast` | `greenhouse_forecast_results_v2` |
| `catalog` | `/api/v1/catalog` | `famiglie_catalog_static`, `mv_famiglie_catalog`, RPC `core_analytics__catalog_children` |
| `sales` | `/api/v1/sales` | `greenhouse_sales_*` views |
| `planner` | `/api/v1/planner` | `t_core_planner__*` (via RPC: `core_planner__get_heat_cells`, `get_fact_weekly`, `get_space_budget`, `get_assortment_calendar`, `get_density`) |
| `ops` | `/api/v1/ops` | `ml_ops.v_*` (11 views) |
| `system` | `/api/v1/system` | Health/metadata only |

### DB connection

Reads from `POSTGRES_HOST/PORT/DB/USER/PASSWORD` env vars (set in `/opt/greenbrain-v2/deploy/.env`).
Points to **local Docker PostgreSQL 17** (`gb_v2_postgres:17` on port 5433), **not** Supabase.

> ⚠️ Important: The Docker backend connects to the local `greenbrain` DB, not the Supabase cloud DB
> where all ETL and ML writes happen. The local DB is a separate instance that must be kept in sync
> or schema-mirrored with Supabase for the API to serve current data.

### Downstream dependency

Layer 11 (Frontend) makes all data requests through this layer. No direct DB access from frontend.

---

## Layer 11: FRONTEND

React SPA consuming the FastAPI backend for all data. Auth via Supabase.

### Runtime

| Container | Image | Port | Source volume |
|-----------|-------|------|---------------|
| `gb_v2_frontend` | node:20-alpine | 8083 (→8080 internal) | `/opt/greenbrain/frontend:/app` |
| `gb_v2_nginx` | nginx:alpine | 8082 | nginx.conf |

### Architecture

```
Browser
  → :8082 nginx (reverse proxy)
  → :8083 Vite dev server (gb_v2_frontend)
  → :8002 FastAPI (gb_v2_backend) for all data calls
  → Supabase cloud for auth only (supabase-js client)
```

### Data hooks (all via FastAPI)

| Hook | Endpoint |
|------|---------|
| `useAnalyticsCompareSeries` | `GET /api/v1/analytics/compare-series` |
| `useAnalyticsEntitySummary` | `GET /api/v1/analytics/entity-summary` |
| `useAnalyticsComponents` | `GET /api/v1/analytics/components` |
| `useAnalyticsRollingTotals` | `GET /api/v1/analytics/series` |
| `useAnalyticsSeasonality` | `GET /api/v1/analytics/seasonality` |
| `useAnalyticsSeriesAllTime` | `GET /api/v1/analytics/series-bounds` |
| `useAnalyticsStockAndReorder` | `GET /api/v1/analytics/stock-and-reorder` |
| `useDashboardSalesWeekly/Monthly/Yearly` | `GET /api/v1/dashboard/sales-*` |
| `useDashboardReorderSuggestions` | `GET /api/v1/dashboard/reorder-suggestions` |
| `useCatalogChildren` | `GET /api/v1/catalog/children` |
| `useForecast*` | `GET /api/v1/forecast/*` |
| `usePlanner*` | `GET /api/v1/planner/*` |

### Auth

`/opt/greenbrain/frontend/src/integrations/supabase/client.ts` uses `@supabase/supabase-js` with `VITE_SUPABASE_URL` + `VITE_SUPABASE_PUBLISHABLE_KEY`. All auth flows (login, session, JWT) go through Supabase cloud directly, bypassing FastAPI.

---

## Cross-Layer Dependencies

### `greenhouse_forecast_features_dense` (Layer 4 output)

The most widely consumed table in the system.

```
Layer 4: FEATURES  ──→  Layer 5: ANALYTICS    (refresh_core_analytics_range)
                   ──→  Layer 6: PARQUET EXPORT (export_features_dense.py reads this)
                   ──→  Layer 7: ML TRAINING   (DB fallback in data_access_v1.py)
                   ──→  Layer 8: ML PREDICTION (DB fallback in data_access_v1.py)
                   ──→  Layer 9: PLANNER       (core_planner__nightly_roll4_tick reads directly)
```

If this table is stale or empty: analytics are wrong, ML uses stale features, planner uses stale actuals.

---

### Supabase Storage parquet (Layer 6 output)

```
Layer 6: PARQUET EXPORT  ──→  Layer 7: ML TRAINING   (primary feature source)
                         ──→  Layer 8: ML PREDICTION (primary feature source)
```

Fallback path (if parquet unavailable or stale): both layers fall back to DB reads of `greenhouse_forecast_features_dense`. Fallback is silent — no error, no alert. Parquet staleness is detectable only via `ops_parquet_export_state.last_success_date`.

---

### DO Spaces model bundles (Layer 7 output)

```
Layer 7: ML TRAINING  ──→  Layer 8: ML PREDICTION
```

`predict_all.py` calls `ensure_model_bundle.py` per family which downloads from DO Spaces.
If bundle is missing: inline training via `AUTO_TRAIN_MISSING=1` (slow, adds 10–30 min per family),
or family is skipped if inline training fails.

---

### `greenhouse_forecast_results_v2` (Layer 8 output)

```
Layer 8: ML PREDICTION  ──→  Layer 9: PLANNER (core_planner__nightly_roll4_tick)
                        ──→  Layer 10: API /api/v1/forecast
                        ──→  Layer 10: API /api/v1/dashboard
```

Written during 01:30–03:00 local. Read by planner at 12:00 UTC (13:00 local). If prediction hasn't completed before 12:00 UTC, planner reads yesterday's results.

---

### `etl.t_etl_runs` (Layer 2 output)

```
Layer 2: ETL  ──→  Layer 6: PARQUET EXPORT (check_etl_ready.sh gates on this)
```

This is the only formal handoff signal between layers. No other layer has a wait/gate mechanism.

---

### `ml_forecast.family_model_registry_v1/v2` (Layer 5/registry output)

```
gh-refresh-registry (00:45 local)  ──→  gh-train-missing (01:10 local)
                                   ──→  gh-predict-all   (01:30 local)
```

`v_train_missing_candidates_v1` (read by train-missing) is derived from `family_model_registry_v1`.
`family_model_registry_v2` gates which families run in predict. If registry is stale, wrong families
are trained/predicted.

---

### Seasonal priors (within Layer 8)

```
build_seasonal_priors.py  →  upload to Supabase Storage  →  download back
                                                          →  predict_v4_single_family_tweedie.py reads priors_v1.parquet
```

Priors are rebuilt fresh each daily run. If `upload_priors_to_supabase` fails, the download step also fails, and predict crashes before processing any family.

---

## Critical Data Paths

### Path 1: ETL success gate

```
gestionale POS system  →  greenhouse_sales_raw  →  run_greenhouse_daily_pipeline_full()
  →  etl.t_etl_runs {status: success}
  →  check_etl_ready.sh passes
  →  gh-parquet-export runs
```

**Break condition:** If gestionale ETL doesn't deliver today's sales before 10:00 UTC, pg_cron #11
runs but produces no new data. ETL may still write `status=success` with yesterday's data range. If
the function has no "data freshness" check, `check_etl_ready.sh` will pass and parquet export will
run on stale features — **no error visible at the parquet layer**.

**Severity:** 🔴 Silent stale data propagates to ML training and prediction.

---

### Path 2: Parquet → ML fallback

```
gh-parquet-export fails or is skipped
  →  data_access_v1.py: PARQUET_ENABLE=1 but file missing
  →  falls back to: SELECT * FROM greenhouse_forecast_features_dense WHERE ...
```

**Break condition:** Parquet export not run, or exported with wrong schema/encoding.

**Severity:** 🟠 HIGH — DB fallback is functional but significantly slower and increases Supabase
DB load. Model quality is identical (same data source). No alert is raised.

---

### Path 3: Train → Predict bundle dependency

```
gh-train-missing (01:10)  →  DO Spaces bundle written
gh-predict-all (01:30)    →  ensure_model_bundle downloads it
```

**Race condition:** If `gh-train-missing` is still running when `gh-predict-all` starts (20-min margin
with no ordering enforcement), `predict-all` may attempt to download a bundle that is being written
concurrently to DO Spaces. `ensure_model_bundle` does not retry on partial download — it checks
existence via `s3.head_object`, which returns 200 even for an in-progress multipart upload.

**Severity:** 🟠 HIGH — rare but possible for large families. Predict would use a corrupt bundle
and produce garbage or crash for that family.

---

### Path 4: Predict → Planner timing

```
gh-predict-all finishes (typically 01:30–03:00 local = 00:30–02:00 UTC)
pg_cron #13 runs at 12:00 UTC  →  reads greenhouse_forecast_results_v2
```

**Timing dependency:** ~10h gap between predict completion and planner tick. Normally safe.

**Break condition:** On biweekly train nights (`gh-train-biweekly-all` starts 01:00 UTC), the full
retrain of all families can take 3–6h. `gh-predict-all` may not start until after train completes
(lock file prevents predict from running while retrain is ongoing — **unconfirmed, depends on lock
implementation**). If predict finishes after 12:00 UTC, planner uses yesterday's forecast.

**Severity:** 🟡 MEDIUM — planner output is 1 day stale. Visible in frontend from 13:00 local.

---

### Path 5: Priors upload/download symmetry

```
build_seasonal_priors.py  →  priors_v1.parquet (local)
upload_priors_to_supabase →  Supabase Storage: priors/priors_v1.parquet
download_priors_from_supabase  →  priors_v1.parquet (local again)
predict_v4_single_family_tweedie.py  →  reads priors_v1.parquet
```

**Break condition:** If `upload_priors_to_supabase` fails (Supabase Storage quota, network), the
subsequent download also fails. `run_predict_all.sh` will abort before any family is predicted.

**Severity:** 🔴 CRITICAL — entire predict job aborts, no forecast written for any family.

**Note:** The upload→download round-trip is designed as a consistency check but adds a second point
of failure. The local file exists before upload; predict could read it directly if upload is skipped.

---

### Path 6: API reads local Docker DB, not Supabase

```
ETL writes  →  Supabase cloud PostgreSQL
API reads   →  local Docker PostgreSQL 17 (gb_v2_postgres)
```

**Break condition:** These are two separate databases. If the local Docker DB is not populated from
Supabase (via dump-restore, logical replication, or other sync), the API returns stale or empty data.

**Severity:** 🔴 CRITICAL — the API and frontend show data only as fresh as the last DB sync.
No sync mechanism is documented in the current stack. This is a **known architecture gap**.

---

## Related documents

| Document | Path |
|----------|------|
| Job catalog (full per-job detail) | `docs/operations/job-catalog.md` |
| Unified schedule | `docs/operations/schedules.md` |
| Full system inventory (all phases) | `docs/operations/00-full-system-inventory-01/02/03.md` |
| Storage migration analysis | `docs/migration/04-storage-migration-analysis.md` |
| Client runtime design | `docs/architecture/02-client-runtime-design.md` |
