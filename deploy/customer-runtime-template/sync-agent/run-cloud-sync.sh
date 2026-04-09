#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/cloud-sync.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Manca $ENV_FILE"
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

python3 /opt/greenbrain-platform/tools/cloud_sync/push_demo_dataset.py \
  "$CLOUD_SYNC_BASE_URL" \
  "$TENANT_CODE" \
  "$CLOUD_SYNC_API_KEY"
