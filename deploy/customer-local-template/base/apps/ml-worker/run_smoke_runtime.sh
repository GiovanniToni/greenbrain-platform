#!/usr/bin/env bash
set -euo pipefail

cd /opt/greenbrain-platform/apps/ml-worker

echo "===== SMOKE EXPORT ====="
./run_export_runtime.sh

echo "===== SMOKE TRAIN ====="
./run_train_runtime.sh "rosa"

echo "===== SMOKE PREDICT ====="
./run_predict_runtime.sh "rosa"

echo "===== SMOKE DONE ====="
