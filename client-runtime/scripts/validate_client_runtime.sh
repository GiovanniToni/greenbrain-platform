#!/usr/bin/env bash
set -euo pipefail

BASE=/opt/greenbrain-platform
cd "$BASE"

echo "=== VALIDATE FILES ==="
test -f apps/ml-worker/jobs/ml_ops_bridge.py
test -f apps/ml-worker/jobs/predict_family_logged.py
test -f apps/ml-worker/jobs/train_family_logged.py
test -f apps/ml-worker/jobs/parquet_export/export_features_dense.py
test -f apps/ml-worker/run_daily_runtime.sh
test -f apps/ml-worker/run_daily_demo_runtime.sh
test -f apps/ml-worker/run_weekly_train_runtime.sh
test -f client-runtime/etl/.env.ml.runtime
test -f client-runtime/etl/run_etl_runtime.sh

echo "=== VALIDATE PY COMPILE ==="
cd "$BASE/apps/ml-worker"
source .venv/bin/activate
python -m py_compile jobs/ml_ops_bridge.py
python -m py_compile jobs/predict_family_logged.py
python -m py_compile jobs/train_family_logged.py
python -m py_compile jobs/predict_family_router.py
python -m py_compile jobs/parquet_export/export_features_dense.py
python -m py_compile data_access_v1.py
python -m py_compile predict_v4_single_family_tweedie.py
python -m py_compile train_v4_single_family_tweedie.py
python -m py_compile jobs/engines/engine_naive_zero.py
python -m py_compile jobs/engines/fascia_allocator.py
python -m py_compile storage/backend.py
python -m py_compile storage/local_storage.py
python -m py_compile storage/storage_interface.py
python -m py_compile jobs/common.py
python -m py_compile jobs/model_control.py
python -m py_compile jobs/validate_engines.py
python -m py_compile jobs/train_all_monitor.py
python -m py_compile jobs/train_missing_batches.py
python -m py_compile jobs/benchmark_family.py
python -m py_compile jobs/diagnose_families.py
python -m py_compile jobs/dump_families.py
python -m py_compile tools/build_seasonal_priors.py
deactivate || true

echo "=== VALIDATE DB OBJECTS ==="
cd "$BASE"
set -a
source client-runtime/etl/.env.ml.runtime
set +a
export PGPASSWORD="$PG_PASSWORD"

psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -Atqc "select 'ok' from information_schema.tables where table_schema='ml_ops' and table_name='pipeline_run_log_v1' limit 1;"
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -Atqc "select 'ok' from information_schema.tables where table_schema='ml_ops' and table_name='family_run_log_v1' limit 1;"
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -Atqc "select 'ok' from information_schema.tables where table_schema='public' and table_name='t_ops_pipeline_monitor' limit 1;"
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -Atqc "select 'ok' from information_schema.tables where table_schema='public' and table_name='greenhouse_forecast_results_v2' limit 1;"

echo "=== VALIDATE RUNTIME WRAPPERS ==="
test -x "$BASE/client-runtime/etl/run_etl_runtime.sh"
test -x "$BASE/apps/ml-worker/run_daily_runtime.sh"
test -x "$BASE/apps/ml-worker/run_daily_demo_runtime.sh"
test -x "$BASE/apps/ml-worker/run_weekly_train_runtime.sh"
test -x "$BASE/apps/ml-worker/run_smoke_runtime.sh"

echo "VALIDATION_OK"
