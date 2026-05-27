#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="$ROOT/overlay/env/customer-local.env"
EXAMPLE="$ROOT/env/customer-local.env.example"

if [ -f "$OUT" ]; then
  echo "generate-customer-env: env exists, skip"; exit 0
fi

[ -f "$EXAMPLE" ] || { echo "ERROR: missing $EXAMPLE" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"

_ask() {
  local label="$1" default="${2:-}" value=""
  if [ -n "$default" ]; then
    printf "%s [%s]: " "$label" "$default" >&2
    IFS= read -r value || true; value="${value:-$default}"
  else
    printf "%s: " "$label" >&2; IFS= read -r value || true
  fi
  printf "%s" "$value"
}

_norm(){ printf "%s" "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g;s/__*/_/g;s/^_//;s/_$//'; }

TC_RAW="${GREENBRAIN_TENANT_CODE:-$(_ask "Tenant code" "cliente_locale")}"
TC="$(_norm "$TC_RAW")"
TN="${GREENBRAIN_TENANT_NAME:-$(_ask "Nome azienda" "Cliente Locale")}"
TH="${GREENBRAIN_TENANT_HOST:-${TC//_/-}.greenbrain.it}"
PDB="${GREENBRAIN_POSTGRES_DB:-greenbrain_${TC}}"
PU="${GREENBRAIN_POSTGRES_USER:-greenbrain_${TC}}"
PP="${GREENBRAIN_POSTGRES_PASSWORD:-$(python3 -c 'import secrets;print(secrets.token_urlsafe(18))')}"
BP="${GREENBRAIN_BACKEND_PORT:-8008}"
FP="${GREENBRAIN_FRONTEND_PORT:-8088}"
JWT="${GREENBRAIN_JWT_SECRET:-$(python3 -c 'import secrets;print(secrets.token_urlsafe(32))')}"
CE="${GREENBRAIN_CUSTOMER_EMAIL:-$(_ask "Email accesso locale" "")}"
CN="${GREENBRAIN_CUSTOMER_FULLNAME:-$(_ask "Nome completo cliente" "$TN")}"
CP="${GREENBRAIN_CUSTOMER_PASSWORD:-$(_ask "Password temporanea (Invio=vuoto)" "")}"
PM="temporary_password"; [ -z "$CP" ] && PM="cloud_password"

export TC TN TH PDB PU PP BP FP JWT CE CN CP PM
python3 - "$EXAMPLE" "$OUT" <<'PY'
import os, sys
from pathlib import Path
ex, out = Path(sys.argv[1]), Path(sys.argv[2])
e = os.environ
ov = {
  "APP_ENV":"client-local","TENANT_CODE":e["TC"],"TENANT_NAME":e["TN"],"TENANT_HOST":e["TH"],
  "POSTGRES_HOST":"postgres","POSTGRES_PORT":"5432","POSTGRES_DB":e["PDB"],
  "POSTGRES_USER":e["PU"],"POSTGRES_PASSWORD":e["PP"],"POSTGRES_SSLMODE":"disable",
  "DATABASE_URL":f"postgresql://{e['PU']}:{e['PP']}@postgres:5432/{e['PDB']}",
  "JWT_SECRET":e["JWT"],"JWT_EXPIRE_MINUTES":"60",
  "LOCAL_BACKEND_PORT":e["BP"],"LOCAL_FRONTEND_PORT":e["FP"],
  "CENTRAL_AUTH_URL":"https://www.greenbrain.it","CENTRAL_TENANT_CODE":e["TC"],
  "REMOTE_ACCESS_MODE":"reverse-tunnel","TUNNEL_ENABLED":"true",
  "LOCAL_CUSTOMER_EMAIL":e["CE"],"LOCAL_CUSTOMER_FULL_NAME":e["CN"],
  "LOCAL_CUSTOMER_TEMP_PASSWORD":e["CP"],"LOCAL_CUSTOMER_PASSWORD_HASH":"",
  "LOCAL_CUSTOMER_PASSWORD_MODE":e["PM"],"LOCAL_CUSTOMER_TENANT_CODE":e["TC"],
  "LOCAL_CUSTOMER_HOME_HOST":e["TH"],"LOCAL_CUSTOMER_HOME_PATH":"/dashboard",
  "LOCAL_CUSTOMER_USER_ROLE":"customer_admin",
}
q = lambda v: f'"{v}"' if (" " in v or "#" in v) else v
lines, seen = [], set()
for raw in ex.read_text().splitlines():
    if "=" in raw and not raw.lstrip().startswith("#"):
        k = raw.split("=",1)[0].strip()
        if k in ov: lines.append(f"{k}={q(str(ov[k]))}"); seen.add(k)
        else: lines.append(raw)
    else: lines.append(raw)
for k,v in ov.items():
    if k not in seen: lines.append(f"{k}={q(str(v))}")
out.write_text("\n".join(lines)+"\n")
PY
echo "Env generato: $OUT"
