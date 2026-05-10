#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV="$ROOT/overlay/env/customer-local.env"

[ -f "$ENV" ] || { echo "ERROR: missing $ENV"; exit 1; }

cd "$ROOT"

echo "== GreenBrain run local daily once =="

LOCAL_UID="${LOCAL_UID:-$(id -u)}"
LOCAL_GID="${LOCAL_GID:-$(id -g)}"
export LOCAL_UID LOCAL_GID

echo "== Fix local ML writable dirs =="
docker compose -f docker-compose.local.yml --env-file "$ENV" run --rm --user root ml-worker \
  bash -lc "mkdir -p /workspace/overlay/logs/ml /workspace/overlay/ml/models_v4 /workspace/overlay/ml/storage && chown -R ${LOCAL_UID}:${LOCAL_GID} /workspace/overlay/logs/ml /workspace/overlay/ml"

docker compose -f docker-compose.local.yml --env-file "$ENV" run --rm ml-worker \
  bash -lc 'cd /workspace && bash base/orchestration/jobs/runtime/run_daily_sequence.sh'

echo
echo "RUN_LOCAL_DAILY_ONCE_OK"
