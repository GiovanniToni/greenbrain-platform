#!/usr/bin/env bash
set -euo pipefail

BASE=/opt/greenbrain-platform
cd "$BASE"

echo "=== GREENBRAIN CLIENT RUNTIME INSTALL ==="

mkdir -p runtime-reports
mkdir -p runtime-reports/tmp
mkdir -p runtime-reports/diagnostics
mkdir -p /opt/greenbrain/storage
mkdir -p /opt/greenbrain/storage/parquet_cache
mkdir -p /opt/greenbrain/models_v4
mkdir -p client-runtime/release
mkdir -p client-runtime/scripts

echo "=== ENSURE ML VENV ==="
cd "$BASE/apps/ml-worker"
if [ ! -d ".venv" ]; then
  python3 -m venv .venv
fi
source .venv/bin/activate
pip install --upgrade pip setuptools wheel
if [ -f requirements.txt ]; then
  pip install -r requirements.txt
fi
deactivate || true

echo "=== ENSURE ETL VENV ==="
cd "$BASE/client-runtime/etl"
if [ ! -d ".venv" ]; then
  python3 -m venv .venv
fi
source .venv/bin/activate
pip install --upgrade pip setuptools wheel
pip install pandas sqlalchemy python-dotenv psycopg2-binary pyodbc
deactivate || true

echo "=== ENSURE ENV FILES ==="
cd "$BASE"
if [ ! -f client-runtime/etl/.env ]; then
  cp client-runtime/etl/.env.template client-runtime/etl/.env
fi

if [ ! -f client-runtime/etl/.env.ml.runtime ]; then
  cp client-runtime/etl/.env.ml.example client-runtime/etl/.env.ml.runtime
fi

echo "=== APPLY RUNTIME SQL ==="
set -a
source client-runtime/etl/.env.ml.runtime
set +a
export PGPASSWORD="$PG_PASSWORD"

for sql in \
  client-runtime/sql/init/21_ml_ops_runtime_fix.sql \
  client-runtime/sql/init/22_ml_strength_runtime_fix.sql \
  client-runtime/sql/init/23_ml_forecast_routing_runtime_fix.sql \
  client-runtime/sql/init/24_ml_forecast_routing_v4_preferred.sql
do
  if [ -f "$sql" ]; then
    echo "APPLY $sql"
    psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -f "$sql"
  fi
done

echo "=== VALIDATE ==="
/opt/greenbrain-platform/client-runtime/scripts/validate_client_runtime.sh

echo "=== INSTALL DONE ==="
