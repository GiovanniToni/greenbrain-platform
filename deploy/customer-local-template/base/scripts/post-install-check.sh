#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "== GreenBrain Post Install Check =="

cd "$ROOT"

echo
echo "== Version =="
cat VERSION
grep package_version release-manifest.yml || true

echo
echo "== Docker services =="
docker compose -f docker-compose.local.yml --env-file overlay/env/customer-local.env ps

echo
echo "== Doctor extended =="
bash base/scripts/doctor-local-extended.sh

echo
echo "== Daily sequence smoke =="
bash base/scripts/run-local-daily-once.sh

echo
echo "== Latest daily status =="
grep -E "STEP 0|SOURCE_DB_IMPORT|STEP 1|GREENBRAIN_LOCAL_DAILY_SEQUENCE_DONE" overlay/logs/daily_sequence_latest.log || true

echo
echo "POST_INSTALL_CHECK_OK"


echo
echo "== Source DB Data Readiness =="
if [ -x base/scripts/check-source-db-data-readiness.sh ]; then
  bash base/scripts/check-source-db-data-readiness.sh || true
else
  echo "SOURCE_DB_DATA_READINESS_CHECK_SCRIPT_MISSING"
fi
