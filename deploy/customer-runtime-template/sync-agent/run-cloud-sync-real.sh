#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/cloud-sync.env"
TMP_JSON="/tmp/gb-cloud-sync-dashboard-kpis.json"

if [ ! -f "$ENV_FILE" ]; then
  echo "Manca $ENV_FILE"
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

python3 /opt/greenbrain-platform/tools/cloud_sync/exporters/export_dashboard_kpis.py \
  "$TENANT_CODE" \
  "$LOCAL_DATABASE_URL" \
  > "$TMP_JSON"

python3 /opt/greenbrain-platform/tools/cloud_sync/push_json_dataset.py \
  "$CLOUD_SYNC_BASE_URL" \
  "$CLOUD_SYNC_API_KEY" \
  "$TMP_JSON"

echo "Sync reale dashboard_kpis completato per tenant: $TENANT_CODE"
