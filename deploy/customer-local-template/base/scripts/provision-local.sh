#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNTIME_ENV="$ROOT/overlay/provisioning/local-runtime.env"
CUSTOMER_ENV="$ROOT/overlay/env/customer-local.env"

fail(){ echo "ERROR: $1" >&2; exit 1; }

[ -f "$CUSTOMER_ENV" ] || fail "missing $CUSTOMER_ENV"
[ -f "$RUNTIME_ENV" ] || fail "missing $RUNTIME_ENV"

ensure_key() {
  local key="$1"
  local value="$2"
  if ! grep -q "^${key}=" "$RUNTIME_ENV"; then
    echo "${key}=${value}" >> "$RUNTIME_ENV"
  elif [ -z "$(grep "^${key}=" "$RUNTIME_ENV" | tail -1 | cut -d= -f2-)" ]; then
    python3 - "$RUNTIME_ENV" "$key" "$value" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); key=sys.argv[2]; val=sys.argv[3]
out=[]
for line in p.read_text().splitlines():
    out.append(f"{key}={val}" if line.startswith(key+"=") else line)
p.write_text("\n".join(out)+"\n")
PY
  fi
}

ensure_key INSTALLATION_ID "$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"

set -a
source "$CUSTOMER_ENV"
source "$RUNTIME_ENV"
set +a

for var in TENANT_CODE TENANT_NAME CENTRAL_PROVISIONING_URL PROVISIONING_TOKEN HEARTBEAT_URL INSTALLATION_ID; do
  val="${!var:-}"
  [ -n "$val" ] || fail "$var missing in runtime/customer env"
  [[ "$val" != CHANGE_ME* ]] || fail "$var still has placeholder value: $val"
done

VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo unknown)"
PUBLIC_BACKEND_URL="https://${TENANT_HOST:-${TENANT_CODE}.greenbrain.it}"

register_runtime_central() {
  echo "Registering runtime with central GreenBrain"

  response_file="$(mktemp)"

  payload="$(
    python3 - <<'GB_REGISTER_PAYLOAD_PY'
import json
import os

tenant_code = os.environ.get("TENANT_CODE", "")
tenant_name = os.environ.get("TENANT_NAME", "") or tenant_code
installation_id = os.environ.get("INSTALLATION_ID", "")
version = os.environ.get("VERSION", "unknown")
public_backend_url = os.environ.get("PUBLIC_BACKEND_URL", "")

print(json.dumps({
    "tenant_code": tenant_code,
    "tenant_name": tenant_name,
    "installation_id": installation_id,
    "version": version,
    "installed_release_version": version,
    "public_backend_url": public_backend_url,
    "connection_mode": "reverse-tunnel",
    "data_mode": "local-db-via-tunnel",
    "sync_enabled": False,
    "runtime_health": "registering",
    "installation_label": "default",
}))
GB_REGISTER_PAYLOAD_PY
  )"

  http_code="$(curl -sS -o "$response_file" -w '%{http_code}' \
    -X POST "$CENTRAL_PROVISIONING_URL" \
    -H "Authorization: Bearer $PROVISIONING_TOKEN" \
    -H "Content-Type: application/json" \
    -H "User-Agent: GreenBrainCustomerLocal/${VERSION} runtime-register" \
    -d "$payload" || true)"

  if [ "$http_code" != "200" ]; then
    echo "CENTRAL_RUNTIME_REGISTER_FAILED http=${http_code}" >&2
    cat "$response_file" >&2 || true
    rm -f "$response_file" || true
    exit 41
  fi

  if ! python3 - "$response_file" <<'GB_REGISTER_RESPONSE_PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
status = data.get("status")
if status != "registered":
    print(f"CENTRAL_RUNTIME_REGISTER_UNEXPECTED_STATUS={status}", file=sys.stderr)
    raise SystemExit(1)
print("CENTRAL_RUNTIME_REGISTER_OK")
GB_REGISTER_RESPONSE_PY
  then
    cat "$response_file" >&2 || true
    rm -f "$response_file" || true
    exit 42
  fi

  rm -f "$response_file" || true
}

register_runtime_central

echo "Provisioning OK"
echo "  tenant: ${TENANT_CODE}"
echo "  installation: ${INSTALLATION_ID}"
echo "  customer env: $CUSTOMER_ENV"
echo "  runtime env: $RUNTIME_ENV"
