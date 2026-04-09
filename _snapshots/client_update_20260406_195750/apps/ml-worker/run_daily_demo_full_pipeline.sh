#!/usr/bin/env bash
set -euo pipefail

BASE=/opt/greenbrain-platform
cd "$BASE"

mkdir -p runtime-reports runtime-reports/tmp

set -a
source client-runtime/etl/.env.ml.runtime
set +a
export PGPASSWORD="$PG_PASSWORD"

echo "===== DEMO FULL PIPELINE START ====="

echo "===== REFRESH FACT ====="
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c \
"select public.refresh_fact_from_raw(current_date - interval '30 day', current_date + interval '1 day');" || true

echo "===== REFRESH DENSE ====="
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c \
"select public.refresh_dense_range_from_fact(current_date - interval '30 day', current_date + interval '30 day');" || true

echo "===== REFRESH FEATURES ====="
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c \
"select public.refresh_forecast_features_dense_range(current_date - interval '30 day', current_date + interval '30 day');" || true

echo "===== REFRESH CATALOG ====="
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c \
"refresh materialized view public.mv_famiglie_catalog;" || true

echo "===== EXPORT ====="
cd "$BASE/apps/ml-worker"
./run_export_runtime.sh

echo "===== PREDICT DEFAULT SET ====="
./run_predict_runtime.sh "rosa" || true
./run_predict_runtime.sh "lavanda" || true
./run_predict_runtime.sh "ficus elastica" || true

echo "===== DEMO FULL PIPELINE DONE ====="
