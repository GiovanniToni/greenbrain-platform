#!/usr/bin/env bash
set -euo pipefail

BASE=/opt/greenbrain-platform
cd "$BASE/apps/ml-worker"

source .venv/bin/activate

echo "===== WEEKLY TRAIN ====="
./run_train_runtime.sh "rosa"
./run_train_runtime.sh "lavanda"
./run_train_runtime.sh "ficus elastica"
echo "===== WEEKLY TRAIN DONE ====="
