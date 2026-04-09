#!/usr/bin/env bash
set -euo pipefail

BASE=/opt/greenbrain-platform
cd "$BASE"

mkdir -p runtime-reports runtime-reports/tmp

set -a
source client-runtime/etl/.env.ml.runtime
set +a
export PGPASSWORD="$PG_PASSWORD"

echo "===== DEMO DAILY START ====="

echo "===== EXPORT ====="
cd "$BASE/apps/ml-worker"
./run_export_runtime.sh

echo "===== PREDICT DEFAULT SET ====="
./run_predict_runtime.sh "rosa" || true
./run_predict_runtime.sh "lavanda" || true
./run_predict_runtime.sh "ficus elastica" || true

echo "===== DEMO DAILY DONE ====="
