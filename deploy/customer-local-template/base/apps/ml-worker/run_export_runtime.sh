#!/usr/bin/env bash
set -euo pipefail

cd /opt/greenbrain-platform/apps/ml-worker
source .venv/bin/activate
set -a
source ../../client-runtime/etl/.env.ml.runtime
set +a

python -m jobs.parquet_export.export_features_dense --full-export
