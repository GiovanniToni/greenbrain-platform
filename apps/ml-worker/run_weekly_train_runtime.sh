#!/usr/bin/env bash

# GREENBRAIN LEGACY NOTICE
# DEPRECATED: old demo weekly train wrapper; replaced by train-missing/biweekly/quarterly timers.
# Keep only for compatibility/manual debugging until cleanup is finalized.
# Do not use this script for canonical production scheduling.

set -euo pipefail

BASE=/opt/greenbrain-platform
cd "$BASE/apps/ml-worker"

source .venv/bin/activate

echo "===== WEEKLY TRAIN ====="
./run_train_runtime.sh "rosa"
./run_train_runtime.sh "lavanda"
./run_train_runtime.sh "ficus elastica"
echo "===== WEEKLY TRAIN DONE ====="
