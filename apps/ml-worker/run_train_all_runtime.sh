#!/usr/bin/env bash
set -euo pipefail

cd /opt/greenbrain-platform/apps/ml-worker
source .venv/bin/activate
set -a
source ../../client-runtime/etl/.env.ml.runtime
set +a

families=(
  "rosa"
  "lavanda"
  "ficus elastica"
)

for fam in "${families[@]}"; do
  echo "===== TRAIN $fam ====="
  python -m jobs.train_family_logged --family "$fam"
done
