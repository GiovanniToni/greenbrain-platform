#!/usr/bin/env bash
set -euo pipefail

cd /opt/greenbrain-platform/apps/ml-worker
source .venv/bin/activate
set -a
source ../../client-runtime/etl/.env.ml.runtime
set +a

python -m jobs.predict_family_logged --family "$1"
