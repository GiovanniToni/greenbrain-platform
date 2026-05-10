#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="$ROOT/overlay/env/customer-local.env"
EXAMPLE="$ROOT/env/customer-local.env.example"

fail(){ echo "ERROR: $1" >&2; exit 1; }

[ -f "$EXAMPLE" ] || fail "missing $EXAMPLE"

mkdir -p "$(dirname "$OUT")"

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

echo "== GreenBrain Customer Env Wizard =="

TENANT_CODE="$(ask "Tenant code" "cliente_reale")"
TENANT_NAME="$(ask "Tenant name" "Cliente Reale")"
TENANT_HOST="$(ask "Tenant public host" "${TENANT_CODE//_/-}.greenbrain.it")"
POSTGRES_DB="$(ask "Local Postgres DB" "greenbrain_${TENANT_CODE}")"
POSTGRES_USER="$(ask "Local Postgres user" "greenbrain_${TENANT_CODE}")"
POSTGRES_PASSWORD="$(ask "Local Postgres password" "CHANGE_ME_DB_PASSWORD")"
LOCAL_BACKEND_PORT="$(ask "Local backend port" "8008")"
LOCAL_FRONTEND_PORT="$(ask "Local frontend port" "8088")"
JWT_SECRET="$(ask "JWT secret" "CHANGE_ME_LOCAL_JWT_SECRET")"

python3 - "$EXAMPLE" "$OUT" <<PY
from pathlib import Path
import sys

example = Path(sys.argv[1])
out = Path(sys.argv[2])

values = {
    "TENANT_CODE": ${TENANT_CODE@Q},
    "TENANT_NAME": ${TENANT_NAME@Q},
    "TENANT_HOST": ${TENANT_HOST@Q},
    "POSTGRES_DB": ${POSTGRES_DB@Q},
    "POSTGRES_USER": ${POSTGRES_USER@Q},
    "POSTGRES_PASSWORD": ${POSTGRES_PASSWORD@Q},
    "POSTGRES_SSLMODE": "disable",
    "DATABASE_URL": f"postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}",
    "LOCAL_BACKEND_PORT": ${LOCAL_BACKEND_PORT@Q},
    "LOCAL_FRONTEND_PORT": ${LOCAL_FRONTEND_PORT@Q},
    "JWT_SECRET": ${JWT_SECRET@Q},
    "CENTRAL_TENANT_CODE": ${TENANT_CODE@Q},
    "LOCAL_CUSTOMER_TENANT_CODE": ${TENANT_CODE@Q},
}

def quote(v: str) -> str:
    if " " in v or "#" in v:
        return '"' + v.replace('"', '\\"') + '"'
    return v

lines = []
seen = set()

for line in example.read_text().splitlines():
    if not line.strip() or line.lstrip().startswith("#") or "=" not in line:
        lines.append(line)
        continue

    k, old = line.split("=", 1)
    if k in values:
        lines.append(f"{k}={quote(str(values[k]))}")
        seen.add(k)
    else:
        lines.append(line)

for k, v in values.items():
    if k not in seen:
        lines.append(f"{k}={quote(str(v))}")

out.write_text("\\n".join(lines) + "\\n")
PY

echo
echo "Customer env generated:"
echo "  $OUT"
