# Table Dependency Graph
> Evidence-based. All reads/writes extracted from Python source + SQL function bodies in `current-schema.sql`.
> No inferences — every arrow is backed by a confirmed `FROM`, `INSERT INTO`, `UPDATE`, or `UPSERT`.

---

## Pipeline Layers

```
RAW  →  ETL  →  DENSE  →  FEATURES  →  ANALYTICS  →  PLANNER
                                   ↘
                                    ML (TRAIN + PREDICT)
                                   ↙          ↘
                          FEATURES (reads)    FORECAST RESULTS (writes)
                                                        ↓
                                              ANALYTICS (reads forecast)
```

---

## Layer 0 — RAW INPUT

Tables populated by external processes (outside workspace).

| Table | Populated by | Notes |
|-------|-------------|-------|
| `public.greenhouse_sales_raw` | External gestionale/POS import | Trigger source for whole pipeline. `data_movimento` = date column, `load_timestamp` = insert time |
| `public.greenhouse_weather_daily` | External (not in workspace) | Joined in features step |
| `public.greenhouse_holidays` | `sync_holidays.py` (manual) | Italian public holidays + local (Firenze, Pistoia) |
| `public.greenhouse_weekday_strength` | `refresh_weekday_strength.py` (manual) | Global weekday multipliers |
| `public.greenhouse_weekday_strength_family` | `refresh_weekday_strength.py` (manual) | Per-family weekday multipliers |

---

## Layer 1 — ETL (RAW → FACT)

**Trigger:** pg_cron `ops_auto_run_after_raw_q5m` (`*/5 19-23 UTC`) → `ops_maybe_run_daily_pipeline()` → `run_greenhouse_daily_pipeline_full(40, 14, 2)` → `daily_etl_postprocess_v3(40)`

**Job:** `public.daily_etl_postprocess_v3(p_rebuild_days)` (SQL function, step B of pipeline)

| Direction | Table | Operation | Details |
|-----------|-------|-----------|---------|
| READ | `public.greenhouse_sales_raw` | SELECT MAX | Detect `target_last` = latest `data_movimento` |
| READ | `public.greenhouse_sales_family_daily_v2` | SELECT | Normalized daily sales VIEW (joins raw + catalog) — rolling last `p_rebuild_days` |
| READ | `public.greenhouse_articoli_da_normalizzare` | SELECT COUNT | Alert if unmapped product codes |
| WRITE | `public.greenhouse_sales_family_daily_fact` | UPSERT ON CONFLICT (data, famiglia, fascia) | Core sales fact — `qty_venduta`, `imponibile_netto_tot`, `num_articoli`, pot sizes |
| WRITE | `public.greenhouse_series_list_fact` | UPSERT ON CONFLICT (famiglia, fascia) | Series catalogue: `first_seen`, `last_seen` per family+fascia combination |
| WRITE | `public.greenhouse_alerts` | UPSERT ON CONFLICT (alert_day, code) | Alerts: `SALES_RAW_EMPTY`, `SALES_RAW_STALE`, `ARTICOLI_DA_NORMALIZZARE` |

**Supporting tables (tracking):**

| Table | Operation | Written by |
|-------|-----------|-----------|
| `etl.t_etl_runs` | INSERT + UPDATE | `etl._start_run()` / `etl._end_run()` around the full procedure |
| `etl.t_etl_steps` | INSERT + UPDATE | `etl._start_step()` / `etl._end_step()` around each step (A/B/C/D/E) |

---

## Layer 2 — DENSE (FACT → DENSE)

**Trigger:** Called inside `daily_etl_postprocess_v3()` after fact upsert

**Job:** `public.refresh_dense_range_from_fact(p_start, p_end)` (SQL function)

| Direction | Table | Operation | Details |
|-----------|-------|-----------|---------|
| READ | `public.greenhouse_sales_family_daily_fact` | LEFT JOIN | Actual sales for date range |
| READ | `public.greenhouse_series_list_fact` | CROSS JOIN | All known (famiglia, fascia) pairs — creates zero-filled rows for missing dates |
| WRITE | `public.greenhouse_sales_family_daily_dense` | UPSERT ON CONFLICT (data, famiglia, fascia) | Zero-padded daily series — every family×fascia×date always present |

**Key transformation:** sparse `fact` (only days with actual sales) → dense `dense` (every calendar day, zero-filled). Ensures ML has contiguous daily series.

---

## Layer 3 — FEATURES (DENSE → FEATURES)

**Trigger:** Called inside `daily_etl_postprocess_v3()` after dense refresh

**Job:** `public.refresh_forecast_features_dense_range(p_start, p_end)` (SQL function)

| Direction | Table | Operation | Details |
|-----------|-------|-----------|---------|
| READ | `public.greenhouse_sales_family_daily_dense` | FROM + window functions | Source qty + lag context window: `p_start - 28 days` to `p_end` |
| READ | `public.greenhouse_weather_daily` | LEFT JOIN on `data` | `tmin_c`, `tmax_c`, `tavg_c`, `rain_mm`, `sun_hours` |
| READ | `public.greenhouse_holidays` | LEFT JOIN on `data` | `is_holiday`, `holiday_name` |
| WRITE | `public.greenhouse_forecast_features_dense` | UPSERT ON CONFLICT (data, famiglia, fascia) | Full feature set: lags (1,2,3,7,10,14), MAs (3,7,10,14,28), weather, holidays, DOW, week_num, month_num, year_num |

---

## Layer 4 — ANALYTICS (FEATURES + FORECAST → ANALYTICS)

### Step B2 — Dashboard aggregates

**Trigger:** Inside `run_greenhouse_daily_pipeline_full()`, step B2

| Direction | Table | Operation | Details |
|-----------|-------|-----------|---------|
| READ | `public.greenhouse_sales_family_daily_dense` | SELECT + GROUP BY | Daily/weekly/monthly aggregates over rolling window |
| WRITE | `public.t_dashboard_sales_daily` | UPSERT ON CONFLICT (data) | Total `qty_tot`, `imp_tot`, `num_articoli_tot` per day |
| WRITE | `public.t_dashboard_sales_weekly` | UPSERT ON CONFLICT (period_start) | Weekly totals |
| WRITE | `public.t_dashboard_sales_monthly` | UPSERT ON CONFLICT (period_start) | Monthly totals |

### Step C0 — MV refresh

**Trigger:** Inside `run_greenhouse_daily_pipeline_full()`, step C0

| Direction | Table | Operation | Details |
|-----------|-------|-----------|---------|
| WRITE | `public.mv_core_analytics__breakdown_daily_fascia_fp` | REFRESH MATERIALIZED VIEW CONCURRENTLY | Pre-aggregated fascia→fp breakdown; needed as input for rollups step C |

### Step B — Daily series aggregates

**Trigger:** `refresh_analytics_aggregates_range(p_start, p_end)` — called inside `daily_etl_postprocess_v3()`

| Direction | Table | Operation | Details |
|-----------|-------|-----------|---------|
| READ | `public.greenhouse_forecast_features_dense` | FROM | Source: qty, categoria, fascia, is_holiday, dow |
| READ | `public.greenhouse_forecast_results_v2` | LEFT JOIN | Forecast qty per day/family/fascia — joined to produce `qty_forecast_tot` alongside actuals |
| WRITE | `public.t_core_analytics__series_daily_famiglia` | UPSERT | Daily qty+revenue+forecast per famiglia |
| WRITE | `public.t_core_analytics__series_daily_categoria` | UPSERT | Daily qty+revenue+forecast per categoria |
| WRITE | `public.t_core_analytics__series_daily_fascia` | UPSERT | Daily qty+revenue+forecast per fascia |
| WRITE | `public.t_core_analytics__series_daily_fascia_prezzo` | UPSERT | Daily qty+revenue+forecast per fascia_prezzo |
| WRITE | `public.t_core_analytics__breakdown_daily_famiglia_fp` | UPSERT | Daily famiglia → fascia_prezzo breakdown |
| WRITE | `public.t_core_analytics__breakdown_daily_categoria_fp` | UPSERT | Daily categoria → fascia_prezzo breakdown |

### Step C — Weekly/Monthly rollups

**Trigger:** Inside `run_greenhouse_daily_pipeline_full()`, step C — `refresh_analytics_rollups_range(p_start, p_end)`

| Direction | Table | Operation | Details |
|-----------|-------|-----------|---------|
| READ | `public.t_core_analytics__series_daily_famiglia` | SELECT + GROUP BY | Source for weekly famiglia series |
| READ | `public.t_core_analytics__series_daily_categoria` | SELECT + GROUP BY | Source for weekly categoria series |
| READ | `public.t_core_analytics__series_daily_fascia` | SELECT + GROUP BY | Source for weekly fascia series |
| READ | `public.t_core_analytics__series_daily_fascia_prezzo` | SELECT + GROUP BY | Source for weekly fascia_prezzo series |
| READ | `public.t_core_analytics__breakdown_daily_famiglia_fp` | SELECT + GROUP BY | Source for weekly famiglia→fp breakdown |
| READ | `public.t_core_analytics__breakdown_daily_categoria_fp` | SELECT + GROUP BY | Source for weekly categoria→fp breakdown |
| READ | `public.mv_core_analytics__breakdown_daily_fascia_fp` | SELECT + GROUP BY | Source for weekly fascia→fp breakdown (uses MV from step C0) |
| WRITE | `public.t_core_analytics__series_weekly_famiglia` | UPSERT | Weekly rolled-up famiglia series |
| WRITE | `public.t_core_analytics__series_weekly_categoria` | UPSERT | Weekly rolled-up categoria series |
| WRITE | `public.t_core_analytics__series_weekly_fascia` | UPSERT | Weekly rolled-up fascia series |
| WRITE | `public.t_core_analytics__series_weekly_fascia_prezzo` | UPSERT | Weekly rolled-up fascia_prezzo series |
| WRITE | `public.t_core_analytics__breakdown_weekly_famiglia_fp` | UPSERT | Weekly famiglia→fp breakdown |
| WRITE | `public.t_core_analytics__breakdown_weekly_categoria_fp` | UPSERT | Weekly categoria→fp breakdown |
| WRITE | `public.t_core_analytics__breakdown_weekly_fascia_fp` | UPSERT | Weekly fascia→fp breakdown |

---

## Layer 5 — ML TRAIN

**Trigger:** systemd `gh-train-missing.timer` (01:10 UTC daily) and `gh-train-biweekly-all.timer` / `gh-train-quarterly.timer`

**Jobs:** `train_missing_batches.py` / `train_all_monitor.py` → `train_family_router.py` → `train_v4_single_family_tweedie.py` (or engine variant)

| Direction | Table / Storage | Operation | Job |
|-----------|----------------|-----------|-----|
| READ | `ml_forecast.v_family_execution_routing_v2` | SELECT | `train_missing_batches.py` / `train_all_monitor.py` — family list + model_code + routing |
| READ | `ml_ops.job_schedule_config_v1` | SELECT `is_enabled` | Job gate check in `ml_ops_bridge.check_job_enabled()` |
| READ | `public.greenhouse_forecast_features_dense` | SELECT (parquet-first) | Training history via `data_access_v1.load_family_df_parquet_or_db()` |
| READ | Supabase Storage `ml-snapshots/features_dense/v1/year=Y/famiglia_slug=S/part.parquet` | Download | Parquet-first fallback for training data (`PARQUET_ENABLE=1`) |
| WRITE | `models_v4/bundle_<slug>_v4.pkl` | Save file | Local model bundle |
| WRITE | DO Spaces `models_v4/bundle_<slug>_v4.pkl` | Upload via boto3 | `ensure_model_bundle.upload_bundle()` after successful train |
| WRITE | `ml_forecast.family_model_state_v1` | UPDATE | `mark_family_train_success_v1` / `mark_family_train_failed_v1` — sets `needs_retrain=false`, `last_trained_at`, `model_code` |
| WRITE | `ml_forecast.model_artifact_registry_v1` | UPSERT | `sync_local_artifacts.py` (ExecStartPost) — registers bundle metadata |
| WRITE | `ml_ops.pipeline_run_log_v1` | INSERT + UPDATE | Start/finish via `ml_ops_bridge.start_pipeline_run` / `finish_pipeline_run` |
| WRITE | `ml_ops.family_run_log_v1` | INSERT + UPDATE | Per-family start/finish via `ml_ops_bridge.start_family_run` / `finish_family_run` |

---

## Layer 5 — ML PREDICT

**Trigger:** systemd `gh-predict-all.timer` (01:30 UTC daily) — runs after `gh-train-missing` (01:10)

**Jobs:** `run_predict_all.sh` → (build priors) → `predict_all.py` → `predict_family_router.py` → `predict_v4_single_family_tweedie.py`

| Direction | Table / Storage | Operation | Job |
|-----------|----------------|-----------|-----|
| READ | `ml_forecast.v_family_execution_routing_v2` | SELECT | `predict_all.py` — all active families |
| READ | `ml_ops.job_schedule_config_v1` | SELECT `is_enabled` | Job gate |
| READ | `public.famiglie_catalog_static` | SELECT slugs | `run_predict_all.sh` step 1 — builds slug list for priors |
| READ | `public.greenhouse_forecast_features_dense` | SELECT (parquet-first) | `build_seasonal_priors.py` — priors computation |
| READ | Supabase Storage `ml-snapshots/features_dense/v1/...` | Download | Parquet loader during predict |
| READ | Supabase Storage `ml-snapshots/priors/priors_v1.parquet` | Download | `download_priors_from_supabase.py` |
| READ | DO Spaces `models_v4/bundle_<slug>_v4.pkl` | Download | `ensure_model_bundle.ensure_bundle_any_engine()` |
| WRITE | Supabase Storage `ml-snapshots/priors/priors_v1.parquet` | Upload | `upload_priors_to_supabase.py` |
| WRITE | `public.greenhouse_forecast_results_v2` | UPSERT ON CONFLICT (data, famiglia, fascia) | Forecast rows ~90 days ahead per family+fascia |
| WRITE | `ml_forecast.family_model_state_v1` | UPDATE | `mark_family_predict_success_v1` / `mark_family_predict_failed_v1` |
| WRITE | `ml_ops.pipeline_run_log_v1` | INSERT + UPDATE | Orchestrator run log |
| WRITE | `ml_ops.family_run_log_v1` | INSERT + UPDATE | Per-family predict run |

---

## Layer 5 — PARQUET EXPORT

**Trigger:** systemd `gh-parquet-export.timer` (21:35 local, after ETL completes)

**Job:** `run_daily_parquet_batches.sh` → `export_features_dense.py`

| Direction | Table / Storage | Operation | Details |
|-----------|----------------|-----------|---------|
| READ | `public.greenhouse_forecast_features_dense` | SELECT | All rows per slug+year batch (BATCH_SIZE=50, offset 0..800) |
| READ | `public.ops_parquet_export_state` | SELECT | Last successful export date per slug+year (incremental mode) |
| READ | `etl.t_etl_runs` | SELECT | `check_etl_ready.sh` guard: ETL must have run today within 12h |
| READ | `public.greenhouse_sales_raw` | SELECT MAX | `check_etl_ready.sh` guard: confirms `raw_last` matches ETL `target_last` |
| WRITE | Supabase Storage `ml-snapshots/features_dense/v1/year=Y/famiglia_slug=S/part.parquet` | Upload | Per-family per-year parquet file |
| WRITE | `public.ops_parquet_export_runs` | INSERT + UPDATE | Batch run log |
| WRITE | `public.ops_parquet_export_state` | UPSERT | Last success per slug+year |

---

## Layer 5 — ML REGISTRY

**Trigger:** systemd `gh-refresh-registry.timer` (00:45 UTC daily, runs first)

**Job:** `gh-refresh-ml-diag` (psql) + `refresh_registry.py`

| Direction | Table | Operation | Details |
|-----------|-------|-----------|---------|
| WRITE | `ml_diag.mv_family_day_base` | REFRESH MATERIALIZED VIEW | (ExecStartPre) |
| WRITE | `ml_diag.mv_family_stats` | REFRESH MATERIALIZED VIEW | |
| WRITE | `ml_diag.mv_family_seasonality` | REFRESH MATERIALIZED VIEW | |
| WRITE | `ml_diag.mv_family_intermittency` | REFRESH MATERIALIZED VIEW | |
| WRITE | `ml_diag.mv_family_importance` | REFRESH MATERIALIZED VIEW | |
| WRITE | `ml_diag.mv_family_metrics_v3` | REFRESH MATERIALIZED VIEW | |
| WRITE | `ml_diag.mv_family_metrics_v3b` | REFRESH MATERIALIZED VIEW | |
| WRITE | `ml_diag.mv_family_metrics_v4` | REFRESH MATERIALIZED VIEW | |
| WRITE | `ml_diag.mv_family_metrics_v5` | REFRESH MATERIALIZED VIEW | |
| READ | `ml_diag.mv_family_*` (9 MVs above) | SELECT | Input to `log_classification_changes_v1()` and `sync_family_model_state_from_registry_v1()` |
| READ | `ml_forecast.family_model_registry_v2` | SELECT | Current model assignments — `sync_family_model_state_from_registry_v1()` reads this |
| READ | `ml_forecast.model_artifact_registry_v1` | SELECT | Bundle availability — `sync_family_model_state_from_artifacts_v1()` reads this |
| WRITE | `ml_forecast.family_model_state_v1` | UPDATE | State flags: `needs_predict=true` (all), classification sync |
| WRITE | `ml_ops.classification_change_log_v1` | INSERT | Diff log of classification changes |
| WRITE | `ml_ops.pipeline_run_log_v1` | INSERT + UPDATE | Registry run log |

---

## Layer 6 — PLANNER

**Trigger:** Inside `run_greenhouse_daily_pipeline_full()`, steps E and E2: `core_planner__refresh_after_import_step()`

### E2-a: `core_planner__refresh_fact_weekly(p_from, p_to)`

| Direction | Table | Operation | Details |
|-----------|-------|-----------|---------|
| READ | `public.greenhouse_sales_family_daily_dense` | SELECT + GROUP BY | Weekly aggregation: qty, rev, days_active, days_zero per week×family×fascia |
| READ | `public.dim_iso_day` | JOIN | ISO week lookup: `week_start`, `week_52`, `iso_year` |
| WRITE | `public.t_core_planner__fact_weekly` | DELETE + INSERT ON CONFLICT | Weekly sales fact for planner heatmap |
| WRITE | `public.t_core_planner__refresh_state` | UPDATE | Last processed day watermark |

### E2-b: `core_planner__refresh_heat_week_week(p_week_52)` / `core_planner__refresh_heat_roll4_week(p_week_52)`

| Direction | Table | Operation | Details |
|-----------|-------|-----------|---------|
| READ | `public.t_core_planner__fact_weekly` | SELECT | Historical weekly qty by family+fascia — basis for heat |
| READ | `public.greenhouse_forecast_results_v2` | SELECT | Future forecast qty — projected forward |
| WRITE | `public.t_core_planner__heat_cells` | DELETE + INSERT | Heat cells (mode=week / roll4): space_m2, share_of_total per node×week |

### E2-c: `core_planner__refresh_potsize_profile()` (conditional: `p_force_potsize` or first run)

| Direction | Table | Operation | Details |
|-----------|-------|-----------|---------|
| READ | `public.greenhouse_sales_family_daily_dense` | SELECT | Last N years of pot size distribution |
| READ | `public.t_core_planner__density` | LEFT JOIN | Reference density (units/m²) per pot size group |
| WRITE | `public.t_core_planner__potsize_profile` | DELETE + INSERT | Per-family pot size distribution and density estimates |

### E2-d: `core_planner__refresh_space_budget(p_mode, p_level)`

| Direction | Table | Operation | Details |
|-----------|-------|-----------|---------|
| READ | `public.t_core_planner__heat_cells` | SELECT + GROUP BY | Source: `space_m2` per node×week |
| WRITE | `public.t_core_planner__space_budget` | DELETE + INSERT | Space allocation by mode (week/roll4) × level (famiglia/categoria): `space_m2_raw`, `space_share` |

### E2-e: `core_planner__refresh_assortment_calendar(p_mode, p_level)`

| Direction | Table | Operation | Details |
|-----------|-------|-----------|---------|
| READ | `public.t_core_planner__space_budget` | SELECT | Space budget per node×week |
| READ | `public.t_core_planner__heat_cells` | SELECT | Heat cell detail for calendar entries |
| WRITE | `public.t_core_planner__assortment_calendar` | DELETE + INSERT | Final assortment calendar: ordered weeks per family, quantities per pot size |

---

## Complete Dependency Graph

```
══════════════════════════════════════════════════════════════════════
LAYER 0 — RAW INPUT
══════════════════════════════════════════════════════════════════════
  greenhouse_sales_raw              ← external POS/gestionale
  greenhouse_weather_daily          ← external weather feed
  greenhouse_holidays               ← sync_holidays.py (manual)
  greenhouse_weekday_strength       ← refresh_weekday_strength.py
  greenhouse_weekday_strength_family← refresh_weekday_strength.py

══════════════════════════════════════════════════════════════════════
LAYER 1 — ETL  (pg_cron: */5 19-23 UTC)
══════════════════════════════════════════════════════════════════════
  greenhouse_sales_raw
    │  SELECT MAX(data_movimento) = target_last
    ▼
  greenhouse_sales_family_daily_v2  (VIEW — normalizes raw + catalog)
    │  SELECT last 40 days
    ▼
  greenhouse_sales_family_daily_fact  ◄─── UPSERT (fact)
  greenhouse_series_list_fact         ◄─── UPSERT (series catalog)
  greenhouse_alerts                   ◄─── UPSERT (stale/empty alerts)
  etl.t_etl_runs                      ◄─── INSERT/UPDATE (run log)
  etl.t_etl_steps                     ◄─── INSERT/UPDATE (step log)

══════════════════════════════════════════════════════════════════════
LAYER 2 — DENSE
══════════════════════════════════════════════════════════════════════
  greenhouse_sales_family_daily_fact
  greenhouse_series_list_fact         ─┐  CROSS JOIN → zero-fill
                                       │
                                       ▼
  greenhouse_sales_family_daily_dense  ◄─── UPSERT (zero-padded)

══════════════════════════════════════════════════════════════════════
LAYER 3 — FEATURES
══════════════════════════════════════════════════════════════════════
  greenhouse_sales_family_daily_dense
  greenhouse_weather_daily            ─┐  LEFT JOIN
  greenhouse_holidays                 ─┘
         │  + window functions (lag 1/2/3/7/10/14 + MA 3/7/10/14/28)
         ▼
  greenhouse_forecast_features_dense  ◄─── UPSERT (features)

══════════════════════════════════════════════════════════════════════
LAYER 4 — ANALYTICS
══════════════════════════════════════════════════════════════════════
  [B2] greenhouse_sales_family_daily_dense
         │
         ├──► t_dashboard_sales_daily     (UPSERT)
         ├──► t_dashboard_sales_weekly    (UPSERT)
         └──► t_dashboard_sales_monthly   (UPSERT)

  [C0] REFRESH MATERIALIZED VIEW
         mv_core_analytics__breakdown_daily_fascia_fp

  [B/refresh_analytics_aggregates_range]
  greenhouse_forecast_features_dense
  greenhouse_forecast_results_v2  ─┐  LEFT JOIN (forecast qty)
                                   │
         ├──► t_core_analytics__series_daily_famiglia        (UPSERT)
         ├──► t_core_analytics__series_daily_categoria       (UPSERT)
         ├──► t_core_analytics__series_daily_fascia          (UPSERT)
         ├──► t_core_analytics__series_daily_fascia_prezzo   (UPSERT)
         ├──► t_core_analytics__breakdown_daily_famiglia_fp  (UPSERT)
         └──► t_core_analytics__breakdown_daily_categoria_fp (UPSERT)

  [C/refresh_analytics_rollups_range]
  t_core_analytics__series_daily_* (4 tables)
  t_core_analytics__breakdown_daily_* (2 tables)
  mv_core_analytics__breakdown_daily_fascia_fp
         │  GROUP BY week / month
         ├──► t_core_analytics__series_weekly_famiglia        (UPSERT)
         ├──► t_core_analytics__series_weekly_categoria       (UPSERT)
         ├──► t_core_analytics__series_weekly_fascia          (UPSERT)
         ├──► t_core_analytics__series_weekly_fascia_prezzo   (UPSERT)
         ├──► t_core_analytics__breakdown_weekly_famiglia_fp  (UPSERT)
         ├──► t_core_analytics__breakdown_weekly_categoria_fp (UPSERT)
         └──► t_core_analytics__breakdown_weekly_fascia_fp    (UPSERT)

══════════════════════════════════════════════════════════════════════
LAYER 5 — ML  (systemd timers 00:45 / 01:10 / 01:30 UTC)
══════════════════════════════════════════════════════════════════════
  [REGISTRY — 00:45]
  ml_diag.mv_family_* (9 MVs, refreshed from greenhouse_forecast_features_dense)
  ml_forecast.family_model_registry_v2
  ml_forecast.model_artifact_registry_v1
         │
         ├──► ml_forecast.family_model_state_v1   (UPDATE: needs_predict=true)
         ├──► ml_ops.classification_change_log_v1 (INSERT)
         └──► ml_ops.pipeline_run_log_v1          (INSERT/UPDATE)

  [TRAIN — 01:10]
  ml_forecast.v_family_execution_routing_v2 ─► family list
  ml_ops.job_schedule_config_v1             ─► gate
  greenhouse_forecast_features_dense (DB or parquet)
  Supabase Storage ml-snapshots/features_dense/...
         │  LightGBM / ETS / Croston / TSB / SARIMA / NAIVE_ZERO
         ├──► models_v4/bundle_<slug>_v4.pkl         (local file)
         ├──► DO Spaces models_v4/bundle_<slug>_v4.pkl (upload)
         ├──► ml_forecast.family_model_state_v1      (mark success/failed)
         ├──► ml_forecast.model_artifact_registry_v1 (UPSERT)
         ├──► ml_ops.pipeline_run_log_v1             (INSERT/UPDATE)
         └──► ml_ops.family_run_log_v1               (INSERT/UPDATE)

  [PREDICT — 01:30]
  ml_forecast.v_family_execution_routing_v2 ─► family list
  ml_ops.job_schedule_config_v1             ─► gate
  greenhouse_forecast_features_dense (parquet)
  Supabase Storage ml-snapshots/priors/priors_v1.parquet
  DO Spaces models_v4/bundle_<slug>_v4.pkl
         │
         ├──► greenhouse_forecast_results_v2  ◄─── UPSERT (~90 days forward)
         ├──► ml_forecast.family_model_state_v1 (mark predict success/failed)
         ├──► ml_ops.pipeline_run_log_v1        (INSERT/UPDATE)
         └──► ml_ops.family_run_log_v1          (INSERT/UPDATE)

  [PARQUET EXPORT — 21:35 local]
  greenhouse_forecast_features_dense
  ops_parquet_export_state
         │
         └──► Supabase Storage ml-snapshots/features_dense/v1/year=Y/...
         └──► ops_parquet_export_runs   (INSERT/UPDATE)
         └──► ops_parquet_export_state  (UPSERT)

══════════════════════════════════════════════════════════════════════
LAYER 6 — PLANNER  (inside ETL pipeline, steps E + E2)
══════════════════════════════════════════════════════════════════════
  greenhouse_sales_family_daily_dense
  dim_iso_day
         │
         └──► t_core_planner__fact_weekly      ◄─── DELETE + INSERT

  t_core_planner__fact_weekly
  greenhouse_forecast_results_v2  (future forecast for heat projection)
         │
         └──► t_core_planner__heat_cells       ◄─── DELETE + INSERT (week + roll4)

  greenhouse_sales_family_daily_dense
  t_core_planner__density
         │
         └──► t_core_planner__potsize_profile  ◄─── DELETE + INSERT

  t_core_planner__heat_cells
         │
         └──► t_core_planner__space_budget     ◄─── DELETE + INSERT (week + roll4)

  t_core_planner__space_budget
  t_core_planner__heat_cells
         │
         └──► t_core_planner__assortment_calendar  ◄─── DELETE + INSERT
```

---

## Tables by Job (Read/Write Matrix)

### ETL Jobs (pg_cron)

| Job | Tables READ | Tables WRITTEN |
|-----|------------|----------------|
| `daily_etl_postprocess_v3` | `greenhouse_sales_raw`, `greenhouse_sales_family_daily_v2`, `greenhouse_articoli_da_normalizzare` | `greenhouse_sales_family_daily_fact`, `greenhouse_series_list_fact`, `greenhouse_alerts` |
| `refresh_dense_range_from_fact` | `greenhouse_sales_family_daily_fact`, `greenhouse_series_list_fact` | `greenhouse_sales_family_daily_dense` |
| `refresh_forecast_features_dense_range` | `greenhouse_sales_family_daily_dense`, `greenhouse_weather_daily`, `greenhouse_holidays` | `greenhouse_forecast_features_dense` |
| `refresh_analytics_aggregates_range` | `greenhouse_forecast_features_dense`, `greenhouse_forecast_results_v2` | `t_core_analytics__series_daily_*` (4), `t_core_analytics__breakdown_daily_*` (2) |
| `dashboard_refresh` (B2) | `greenhouse_sales_family_daily_dense` | `t_dashboard_sales_daily`, `t_dashboard_sales_weekly`, `t_dashboard_sales_monthly` |
| `REFRESH MV` (C0) | *(MV definition)* | `mv_core_analytics__breakdown_daily_fascia_fp` |
| `refresh_analytics_rollups_range` (C) | `t_core_analytics__series_daily_*` (4), `t_core_analytics__breakdown_daily_*` (2), `mv_core_analytics__breakdown_daily_fascia_fp` | `t_core_analytics__series_weekly_*` (4), `t_core_analytics__breakdown_weekly_*` (3) |
| `core_planner__refresh_fact_weekly` | `greenhouse_sales_family_daily_dense`, `dim_iso_day` | `t_core_planner__fact_weekly`, `t_core_planner__refresh_state` |
| `core_planner__refresh_heat_week_step` | `t_core_planner__fact_weekly`, `greenhouse_forecast_results_v2` | `t_core_planner__heat_cells` |
| `core_planner__refresh_potsize_profile` | `greenhouse_sales_family_daily_dense`, `t_core_planner__density` | `t_core_planner__potsize_profile` |
| `core_planner__refresh_space_budget` | `t_core_planner__heat_cells` | `t_core_planner__space_budget` |
| `core_planner__refresh_assortment_calendar` | `t_core_planner__space_budget`, `t_core_planner__heat_cells` | `t_core_planner__assortment_calendar` |

### ML Jobs (systemd)

| Job | Tables READ | Tables WRITTEN |
|-----|------------|----------------|
| `refresh_registry.py` (00:45) | `ml_forecast.family_model_registry_v2`, `ml_forecast.model_artifact_registry_v1`, `ml_diag.mv_family_*` | `ml_forecast.family_model_state_v1`, `ml_ops.classification_change_log_v1`, `ml_ops.pipeline_run_log_v1` |
| `train_missing_batches.py` (01:10) | `ml_forecast.v_family_execution_routing_v2`, `ml_ops.job_schedule_config_v1`, `greenhouse_forecast_features_dense` | `ml_forecast.family_model_state_v1`, `ml_forecast.model_artifact_registry_v1`, `ml_ops.pipeline_run_log_v1`, `ml_ops.family_run_log_v1` |
| `predict_all.py` (01:30) | `ml_forecast.v_family_execution_routing_v2`, `ml_ops.job_schedule_config_v1`, `greenhouse_forecast_features_dense`, `famiglie_catalog_static` | `greenhouse_forecast_results_v2`, `ml_forecast.family_model_state_v1`, `ml_ops.pipeline_run_log_v1`, `ml_ops.family_run_log_v1` |
| `export_features_dense.py` (21:35) | `greenhouse_forecast_features_dense`, `ops_parquet_export_state`, `etl.t_etl_runs`, `greenhouse_sales_raw` | `ops_parquet_export_runs`, `ops_parquet_export_state` |
| `train_all_monitor.py` (biweekly + quarterly) | `ml_forecast.v_family_execution_routing_v2`, `ml_ops.job_schedule_config_v1`, `greenhouse_forecast_features_dense` | Same as `train_missing_batches.py` |
| `benchmark_family.py` (manual) | `greenhouse_forecast_features_dense`, `ml_forecast.family_model_registry_v2`, `ml_forecast.family_model_assignment_v1`, `ml_forecast.family_model_state_v1` | `ml_forecast.family_model_benchmark_v1`, `ml_forecast.family_model_suggestion_benchmark_v1` |

---

## Cross-layer Table: `greenhouse_forecast_results_v2`

This table is **written by ML predict** and **read by Analytics**, creating the critical join between the forecast and analytics layers:

```
ML PREDICT → greenhouse_forecast_results_v2 → refresh_analytics_aggregates_range
                                             → core_planner__refresh_heat_week
                                             → Frontend /api/v1/forecast/series
```

It is the only table that flows **upward** from ML back into ETL-downstream analytics. Every time `predict_all.py` runs (01:30 UTC), the next ETL run will pick up the new forecasts and re-embed them into all analytics serving tables.

---

## Key Shared Reference Tables (READ-only in pipeline)

| Table | Read by |
|-------|---------|
| `public.dim_iso_day` | `core_planner__refresh_fact_weekly` |
| `public.t_core_planner__density` | `core_planner__refresh_potsize_profile` |
| `public.famiglie_catalog_static` | `run_predict_all.sh` (slugs for priors build) |
| `public.v_famiglie_catalog` | `train_all_batches.py` (legacy) |
| `public.mv_famiglie_catalog` | `train_all_batches.py` (legacy), `predict_all.py` fallback |
