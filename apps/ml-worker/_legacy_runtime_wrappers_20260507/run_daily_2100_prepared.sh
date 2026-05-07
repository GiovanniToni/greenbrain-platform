#!/usr/bin/env bash

# GREENBRAIN LEGACY NOTICE
# DEPRECATED: superseded by gh-daily-pipeline + gh-parquet-export + gh-predict-all systemd timers.
# Keep only for compatibility/manual debugging until cleanup is finalized.
# Do not use this script for canonical production scheduling.

set -euo pipefail

BASE=/opt/greenbrain-platform
cd "$BASE"

echo "=== GREENBRAIN DAILY 21:00 PREPARED RUN ==="

echo "=== STEP 0: ETL SAFE CHECK ==="
if ! /opt/greenbrain-platform/client-runtime/etl/run_etl_runtime.sh; then
  echo "[STOP] ETL non eseguibile o sorgente placeholder. Run interrotto in modo sicuro."
  exit 1
fi

echo "=== STEP 1: LOAD ML ENV ==="
set -a
source client-runtime/etl/.env.ml.runtime
set +a
export PGPASSWORD="$PG_PASSWORD"

echo "=== STEP 2: RAW -> FACT ==="
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "
select public.refresh_fact_from_raw(current_date - interval '30 day', current_date + interval '1 day');
"

echo "=== STEP 3: FACT -> DENSE ==="
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "
select public.refresh_dense_range_from_fact(current_date - interval '30 day', current_date + interval '30 day');
"

echo "=== STEP 4: DENSE -> FEATURES ==="
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "
select public.refresh_forecast_features_dense_range(current_date - interval '30 day', current_date + interval '30 day');
"

echo "=== STEP 5: REFRESH MV ==="
psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "
refresh materialized view public.mv_famiglie_catalog;
"

echo "=== STEP 6: EXPORT ==="
/opt/greenbrain-platform/apps/ml-worker/run_export_runtime.sh

echo "=== STEP 7: PREDICT ALL ==="
/opt/greenbrain-platform/apps/ml-worker/run_predict_all_runtime.sh

echo "=== DAILY 21:00 PREPARED RUN DONE ==="
