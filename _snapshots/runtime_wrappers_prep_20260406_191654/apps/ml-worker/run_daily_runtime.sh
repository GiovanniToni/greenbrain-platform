#!/usr/bin/env bash
set -euo pipefail

cd /opt/greenbrain-platform
set -a
source client-runtime/etl/.env.ml.runtime
set +a

export PGPASSWORD="$PG_PASSWORD"

echo "===== ETL ====="
/opt/greenbrain-platform/client-runtime/etl/run_etl_runtime.sh

echo "===== DATA PIPELINE ====="
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "select public.refresh_fact_from_raw(current_date - interval '30 day', current_date + interval '1 day');" || true
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "select public.refresh_dense_range_from_fact(current_date - interval '30 day', current_date + interval '30 day');" || true
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "select public.refresh_forecast_features_dense_range(current_date - interval '30 day', current_date + interval '30 day');" || true
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "refresh materialized view public.mv_famiglie_catalog;" || true

echo "===== EXPORT ====="
/opt/greenbrain-platform/apps/ml-worker/run_export_runtime.sh

echo "===== PREDICT ALL ====="
/opt/greenbrain-platform/apps/ml-worker/run_predict_all_runtime.sh

echo "===== DAILY DONE ====="
