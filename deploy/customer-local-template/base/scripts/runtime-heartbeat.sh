#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="$ROOT/overlay/provisioning/local-runtime.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "missing env file"
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

if [ "${HEARTBEAT_ENABLED:-false}" != "true" ]; then
  echo "heartbeat disabled"
  exit 0
fi

echo "heartbeat placeholder"
echo "POST -> ${HEARTBEAT_URL:-missing}"
