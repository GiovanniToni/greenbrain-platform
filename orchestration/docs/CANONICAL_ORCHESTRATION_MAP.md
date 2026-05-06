# GreenBrain — Canonical Orchestration Map

## Pipeline giornaliera dev / cliente

### 1. RAW → FACT → DENSE → FEATURES → MONITOR
Canonical:
- infra/systemd/gh-daily-pipeline.service
- infra/systemd/gh-daily-pipeline.timer

DB procedure:
- public.run_greenhouse_daily_pipeline_full(...)
- public.daily_etl_postprocess_v3(...)
- public.ops_refresh_pipeline_monitor_snapshot()

Output principali:
- public.greenhouse_sales_family_daily_fact
- public.greenhouse_sales_family_daily_dense
- public.greenhouse_forecast_features_dense
- public.t_ops_pipeline_monitor
- public.v_ops_pipeline_status

Schedule:
- 21:05 daily

---

### 2. FEATURES → PARQUET
Canonical:
- infra/systemd/gh-parquet-export.service
- infra/systemd/gh-parquet-export.timer
- apps/ml-worker/jobs/parquet_export/scripts/run_daily_parquet_batches.sh
- apps/ml-worker/jobs/parquet_export/export_features_dense.py

Schedule:
- 21:36 daily

---

### 3. FAMILY REGISTRY
Canonical:
- infra/systemd/gh-refresh-registry.service
- infra/systemd/gh-refresh-registry.timer
- infra/scripts/bin/gh-refresh-registry
- apps/ml-worker/jobs/refresh_registry.py

Schedule:
- 00:45 daily

---

### 4. TRAIN MISSING
Canonical:
- infra/systemd/gh-train-missing.service
- infra/systemd/gh-train-missing.timer
- apps/ml-worker/jobs/run_train_missing.sh
- apps/ml-worker/jobs/train_missing_batches.py

Schedule:
- 01:11 daily

---

### 5. PREDICT ALL
Canonical:
- infra/systemd/gh-predict-all.service
- infra/systemd/gh-predict-all.timer
- apps/ml-worker/jobs/run_predict_all.sh
- apps/ml-worker/jobs/predict_all.py

Schedule:
- 01:30 daily

---

### 6. FULL / PERIODIC TRAINING
Canonical:
- infra/systemd/gh-train-biweekly-all.service
- infra/systemd/gh-train-biweekly-all.timer
- infra/systemd/gh-train-quarterly.service
- infra/systemd/gh-train-quarterly.timer
- apps/ml-worker/jobs/run_train_all_parallel.sh
- apps/ml-worker/jobs/train_all_monitor.py

Schedule:
- biweekly: 1 and 15 of each month
- quarterly: Jan/Apr/Jul/Oct 1st

---

## Legacy / demo candidates

Da valutare prima di eliminare:
- apps/ml-worker/run_daily_2100_prepared.sh
- apps/ml-worker/run_daily_demo_full_pipeline.sh
- apps/ml-worker/run_daily_runtime.sh
- apps/ml-worker/run_daily_demo_runtime.sh
- apps/ml-worker/run_nightly_runtime.sh
- apps/ml-worker/run_smoke_runtime.sh
- apps/ml-worker/run_weekly_train_runtime.sh

## Files da archiviare o rimuovere dopo conferma
- *.bak*
- *.orig_*
- __pycache__
- client-runtime/etl/.venv
- client-runtime/etl/__pycache__
- tmp/
