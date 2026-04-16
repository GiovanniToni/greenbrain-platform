#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Uso:"
  echo "  prepare_assigned_bundle.sh <customer_id>"
  exit 1
fi

CUSTOMER_ID="$1"
ROOT="/opt/greenbrain-platform"
OUT_BASE="$ROOT/runtime-reports/customer-delivery"
mkdir -p "$OUT_BASE"

SUPABASE_URL="$(grep '^SUPABASE_URL=' "$ROOT/infra/env/dev.env" | cut -d= -f2-)"
SUPABASE_SERVICE_ROLE_KEY="$(grep '^SUPABASE_SERVICE_ROLE_KEY=' "$ROOT/infra/env/dev.env" | cut -d= -f2- | sed 's/^"//; s/"$//')"

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_SERVICE_ROLE_KEY" ]; then
  echo "ERRORE: SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY mancanti in infra/env/dev.env"
  exit 1
fi

JSON="$(python3 - <<PY
import json
import urllib.request

customer_id = "${CUSTOMER_ID}"
url = "${SUPABASE_URL}/rest/v1/gb_customer_companies?customer_id=eq." + customer_id + "&select=*"
req = urllib.request.Request(url)
req.add_header("apikey", "${SUPABASE_SERVICE_ROLE_KEY}")
req.add_header("Authorization", "Bearer ${SUPABASE_SERVICE_ROLE_KEY}")
req.add_header("Accept", "application/json")

with urllib.request.urlopen(req) as resp:
    rows = json.loads(resp.read().decode("utf-8"))

if not rows:
    raise SystemExit("customer_not_found")

print(json.dumps(rows[0]))
PY
)"

TENANT_CODE="$(printf '%s' "$JSON" | python3 -c 'import sys,json; print((json.load(sys.stdin).get("tenant_code") or "").strip())')"
COMPANY_NAME="$(printf '%s' "$JSON" | python3 -c 'import sys,json; print((json.load(sys.stdin).get("company_name") or "").strip())')"
ASSIGNED_RELEASE_VERSION="$(printf '%s' "$JSON" | python3 -c 'import sys,json; print((json.load(sys.stdin).get("assigned_release_version") or "").strip())')"
ONBOARDING_STATUS="$(printf '%s' "$JSON" | python3 -c 'import sys,json; print((json.load(sys.stdin).get("onboarding_status") or "draft").strip())')"
INSTALL_STATUS="$(printf '%s' "$JSON" | python3 -c 'import sys,json; print((json.load(sys.stdin).get("install_status") or "not_started").strip())')"

if [ -z "$ASSIGNED_RELEASE_VERSION" ]; then
  echo "ERRORE: assigned_release_version mancante per customer_id=$CUSTOMER_ID"
  exit 1
fi

SLUG="$(printf '%s' "${TENANT_CODE:-$COMPANY_NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')"
OUT_DIR="$OUT_BASE/$SLUG"

bash "$ROOT/tools/customer_runtime/prepare_customer_delivery_bundle.sh" "$ASSIGNED_RELEASE_VERSION" "$OUT_DIR"

BUNDLE_DIR="$OUT_DIR/greenbrain-customer-local-$ASSIGNED_RELEASE_VERSION"
ARCHIVE_PATH="$BUNDLE_DIR/customer-local-$ASSIGNED_RELEASE_VERSION.tar.gz"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

[ -f "$ARCHIVE_PATH" ] || { echo "ERRORE: bundle archive non trovato: $ARCHIVE_PATH"; exit 1; }

python3 - <<PY
import json
import urllib.request

url = "${SUPABASE_URL}/rest/v1/gb_customer_delivery?on_conflict=customer_id"
payload = {
    "customer_id": "${CUSTOMER_ID}",
    "assigned_release_version": "${ASSIGNED_RELEASE_VERSION}",
    "bundle_generated_at": "${GENERATED_AT}",
    "bundle_local_path": "${ARCHIVE_PATH}",
    "onboarding_status": "${ONBOARDING_STATUS}",
    "install_status": "${INSTALL_STATUS}",
}

data = json.dumps(payload).encode("utf-8")
req = urllib.request.Request(url, data=data, method="POST")
req.add_header("apikey", "${SUPABASE_SERVICE_ROLE_KEY}")
req.add_header("Authorization", "Bearer ${SUPABASE_SERVICE_ROLE_KEY}")
req.add_header("Content-Type", "application/json")
req.add_header("Prefer", "resolution=merge-duplicates,return=representation")

with urllib.request.urlopen(req) as resp:
    print(resp.read().decode("utf-8"))
PY

echo
echo "Bundle pronto:"
echo "  $ARCHIVE_PATH"
