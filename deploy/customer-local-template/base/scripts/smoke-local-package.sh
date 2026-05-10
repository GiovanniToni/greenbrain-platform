#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

echo "== syntax checks =="
bash -n install.sh
bash -n base/scripts/provision-local.sh
bash -n base/scripts/doctor-local.sh
bash -n base/scripts/doctor-local-extended.sh
bash -n base/scripts/apply-local-sql-patches.sh
bash -n base/scripts/runtime-heartbeat.sh
bash -n base/scripts/setup-source-db.sh
bash -n base/orchestration/lib/common.sh
bash -n base/orchestration/jobs/pipeline/run_daily_pipeline.sh
bash -n base/orchestration/jobs/ml/run_train_missing_local.sh
bash -n base/orchestration/jobs/ml/run_predict_all_local.sh
bash -n base/orchestration/jobs/runtime/run_daily_sequence.sh

echo "== prepare overlay env if missing =="
mkdir -p overlay/env overlay/provisioning overlay/logs overlay/ml/models_v4 overlay/ml/storage
if [ ! -f overlay/env/customer-local.env ]; then
  cp env/customer-local.env.example overlay/env/customer-local.env
fi

echo "== compose config =="
docker compose -f docker-compose.local.yml --env-file overlay/env/customer-local.env config >/tmp/gb_customer_local_compose_check.yml

echo "== version =="
cat VERSION
grep package_version release-manifest.yml

echo "SMOKE_LOCAL_PACKAGE_OK"
