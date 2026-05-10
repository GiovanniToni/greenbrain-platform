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

echo "Provisioning OK"
echo "  tenant: ${TENANT_CODE}"
echo "  installation: ${INSTALLATION_ID}"
echo "  customer env: $CUSTOMER_ENV"
echo "  runtime env: $RUNTIME_ENV"
