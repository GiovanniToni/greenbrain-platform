#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV="$ROOT/overlay/env/customer-local.env"

[ -f "$ENV" ] || { echo "ERROR: missing $ENV"; exit 1; }

cd "$ROOT"

echo "== GreenBrain run local daily once =="

docker compose -f docker-compose.local.yml --env-file "$ENV" run --rm ml-worker \
  bash -lc 'cd /workspace && bash base/orchestration/jobs/runtime/run_daily_sequence.sh'

echo
echo "RUN_LOCAL_DAILY_ONCE_OK"
