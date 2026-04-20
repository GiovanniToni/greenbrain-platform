#!/usr/bin/env bash
set -euo pipefail

BASE=/opt/greenbrain-platform
cd "$BASE"

mkdir -p runtime-reports runtime-reports/tmp

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

echo "===== ETL TRACKING ====="
SUPABASE_PG_PASSWORD="$(grep '^PG_PASSWORD=' /opt/greenbrain-platform/infra/env/dev.env | cut -d= -f2-)"
PGPASSWORD="$SUPABASE_PG_PASSWORD" psql \
  "host=aws-1-eu-west-1.pooler.supabase.com port=5432 dbname=postgres user=postgres.xbyhmzrlycixxrfjggvn sslmode=require" \
  -c "INSERT INTO etl.t_etl_runs (pipeline, status, payload)
      SELECT
        'greenhouse_daily_full',
        'success',
        jsonb_build_object(
          'target_last',
          (select max(data_movimento)::date::text from public.greenhouse_sales_raw),
          'rebuild_days',
          30
        );" \
  && echo "[ETL TRACKING] written to Supabase etl.t_etl_runs" \
  || echo "[ETL TRACKING] WARN: write failed"

echo "===== EXPORT ====="
cd "$BASE/apps/ml-worker"
./run_export_runtime.sh

echo "===== PREDICT DEFAULT SET ====="
./run_predict_runtime.sh "rosa" || true
./run_predict_runtime.sh "lavanda" || true
./run_predict_runtime.sh "ficus elastica" || true

echo "===== DAILY DONE ====="
