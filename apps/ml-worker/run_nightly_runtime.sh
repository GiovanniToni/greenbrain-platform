#!/usr/bin/env bash
set -euo pipefail

cd /opt/greenbrain-platform/apps/ml-worker
source .venv/bin/activate
set -a
source ../../client-runtime/etl/.env.ml.runtime
set +a

echo "===== EXPORT ====="
/opt/greenbrain-platform/apps/ml-worker/run_export_runtime.sh

echo "===== TRAIN ALL ====="
/opt/greenbrain-platform/apps/ml-worker/run_train_all_runtime.sh

echo "===== PREDICT ALL ====="
/opt/greenbrain-platform/apps/ml-worker/run_predict_all_runtime.sh

echo "===== NIGHTLY DONE ====="
