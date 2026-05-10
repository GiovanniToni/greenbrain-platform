#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="$ROOT/overlay/provisioning/local-runtime.env"
CUSTOMER_ENV="$ROOT/overlay/env/customer-local.env"

mkdir -p "$(dirname "$OUT")"

q() {
  python3 - "$1" <<'PY'
import shlex, sys
print(shlex.quote(sys.argv[1]))
PY
}

ask() {
  local label="$1"
  local default="${2:-}"
  local value=""

  if [ -n "$default" ]; then
    read -rp "$label [$default]: " value || true
    value="${value:-$default}"
  else
    read -rp "$label: " value || true
  fi

  echo "$value"
}

echo "== GreenBrain Provisioning Wizard =="

[ -f "$CUSTOMER_ENV" ] || { echo "ERROR: missing $CUSTOMER_ENV"; exit 1; }

set -a
source "$CUSTOMER_ENV"
set +a

TENANT_CODE_VALUE="${TENANT_CODE:-${CENTRAL_TENANT_CODE:-}}"
TENANT_NAME_VALUE="${TENANT_NAME:-$TENANT_CODE_VALUE}"

[ -n "$TENANT_CODE_VALUE" ] || { echo "ERROR: missing TENANT_CODE in customer env"; exit 2; }
[ -n "$TENANT_NAME_VALUE" ] || { echo "ERROR: missing TENANT_NAME in customer env"; exit 3; }

echo "Tenant code: $TENANT_CODE_VALUE"
echo "Tenant name: $TENANT_NAME_VALUE"

PROVISIONING_TOKEN_VALUE="$(ask "Provisioning token")"

CENTRAL_AUTH_URL="https://www.greenbrain.it"
CENTRAL_PROVISIONING_URL="https://www.greenbrain.it/api/v1/customer-runtime/register"
HEARTBEAT_URL="https://www.greenbrain.it/api/v1/customer-runtime/heartbeat"

cat > "$OUT" <<EOF
TENANT_CODE=$(q "$TENANT_CODE_VALUE")
TENANT_NAME=$(q "$TENANT_NAME_VALUE")
CENTRAL_AUTH_URL=$(q "$CENTRAL_AUTH_URL")
CENTRAL_PROVISIONING_URL=$(q "$CENTRAL_PROVISIONING_URL")
PROVISIONING_TOKEN=$(q "$PROVISIONING_TOKEN_VALUE")
INSTALLATION_ID=
HEARTBEAT_ENABLED=true
HEARTBEAT_URL=$(q "$HEARTBEAT_URL")
HEARTBEAT_INTERVAL_SECONDS=300
EOF

echo
echo "Runtime env generated:"
echo "  $OUT"
