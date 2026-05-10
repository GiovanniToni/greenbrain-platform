#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

OUT="$ROOT/overlay/provisioning/local-runtime.env"

echo "== GreenBrain Provisioning Wizard =="

ask() {
  local var="$1"
  local label="$2"
  local default="${3:-}"

  local value=""

  if [ -n "$default" ]; then
    read -rp "$label [$default]: " value || true
    value="${value:-$default}"
  else
    read -rp "$label: " value || true
  fi

  echo "$value"
}

TENANT_CODE="$(ask TENANT_CODE "Tenant code")"
TENANT_NAME="$(ask TENANT_NAME "Tenant name")"
PROVISIONING_TOKEN="$(ask PROVISIONING_TOKEN "Provisioning token")"

CENTRAL_AUTH_URL="https://www.greenbrain.it"
CENTRAL_PROVISIONING_URL="https://www.greenbrain.it/api/v1/customer-runtime/register"
HEARTBEAT_URL="https://www.greenbrain.it/api/v1/customer-runtime/heartbeat"

cat > "$OUT" <<EOF
TENANT_CODE=${TENANT_CODE}
TENANT_NAME="${TENANT_NAME}"
CENTRAL_AUTH_URL=${CENTRAL_AUTH_URL}
CENTRAL_PROVISIONING_URL=${CENTRAL_PROVISIONING_URL}
PROVISIONING_TOKEN=${PROVISIONING_TOKEN}
INSTALLATION_ID=
HEARTBEAT_ENABLED=true
HEARTBEAT_URL=${HEARTBEAT_URL}
HEARTBEAT_INTERVAL_SECONDS=300
EOF

echo
echo "Runtime env generated:"
echo "  $OUT"
