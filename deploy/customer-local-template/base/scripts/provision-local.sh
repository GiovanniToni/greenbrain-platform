#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

RUNTIME_ENV="$ROOT/overlay/provisioning/local-runtime.env"
CUSTOMER_ENV="$ROOT/overlay/env/customer-local.env"

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

[ -f "$RUNTIME_ENV" ] || fail "missing $RUNTIME_ENV"
[ -f "$CUSTOMER_ENV" ] || fail "missing $CUSTOMER_ENV"

if ! grep -q '^INSTALLATION_ID=' "$RUNTIME_ENV"; then
  echo "INSTALLATION_ID=$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)" >> "$RUNTIME_ENV"
fi

CURRENT_ID="$(grep '^INSTALLATION_ID=' "$RUNTIME_ENV" | cut -d= -f2- || true)"
if [ -z "$CURRENT_ID" ]; then
  TMP_ID="$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"
  python3 - "$RUNTIME_ENV" "$TMP_ID" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
new_id = sys.argv[2]
lines = p.read_text().splitlines()
out = []
done = False

for line in lines:
    if line.startswith("INSTALLATION_ID="):
        out.append(f"INSTALLATION_ID={new_id}")
        done = True
    else:
        out.append(line)

if not done:
    out.append(f"INSTALLATION_ID={new_id}")

p.write_text("\n".join(out) + "\n")
PY
fi

set -a
source "$CUSTOMER_ENV"
set +a
set -a
source "$RUNTIME_ENV"
set +a

echo "Provisioning OK"
echo "  tenant: ${TENANT_CODE:-missing}"
echo "  installation: ${INSTALLATION_ID:-missing}"
echo "  customer env preserved: $CUSTOMER_ENV"
