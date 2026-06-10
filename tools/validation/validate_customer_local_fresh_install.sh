#!/usr/bin/env bash
set -euo pipefail

VERSION=""
EXPECTED_COMMIT=""
TENANT_CODE=""
EMAIL=""
PASSWORD=""
CONFIRM_DESTROY="no"

usage() {
  cat <<'USAGE'
Usage:
  validate_customer_local_fresh_install.sh \
    --version <version> \
    --expected-commit <git_commit> \
    --tenant <tenant_code> \
    --email <email> \
    --password <cloud_password> \
    --confirm-destroy-local-test-runtime

Example:
  tools/validation/validate_customer_local_fresh_install.sh \
    --version 0.1.138 \
    --expected-commit 4eeb84945b3a6e3118bc9811ce09c084b93a993d \
    --tenant z \
    --email z@gmail.com \
    --password '********' \
    --confirm-destroy-local-test-runtime

Safety:
  This script performs a fresh local runtime install test in /tmp.
  It may stop and remove only the standard GreenBrain local test containers:

    greenbrain_local_backend
    greenbrain_local_frontend
    greenbrain_local_postgres
    greenbrain_local_ml_worker
    gb_customer_scheduler

  It may remove the standard local test postgres Docker volumes:

    greenbrain_local_postgres_data
    customer-local-template_greenbrain_local_postgres_data

  It will not run unless --confirm-destroy-local-test-runtime is provided.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --expected-commit)
      EXPECTED_COMMIT="${2:-}"
      shift 2
      ;;
    --tenant)
      TENANT_CODE="${2:-}"
      shift 2
      ;;
    --email)
      EMAIL="${2:-}"
      shift 2
      ;;
    --password)
      PASSWORD="${2:-}"
      shift 2
      ;;
    --confirm-destroy-local-test-runtime)
      CONFIRM_DESTROY="yes"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 2
      ;;
  esac
done

if [ -z "$VERSION" ] || [ -z "$EXPECTED_COMMIT" ] || [ -z "$TENANT_CODE" ] || [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
  echo "Missing required argument."
  usage
  exit 2
fi

if [ "$CONFIRM_DESTROY" != "yes" ]; then
  echo "Refusing to run fresh install validation without explicit confirmation."
  echo "Add: --confirm-destroy-local-test-runtime"
  exit 3
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REL="$ROOT/releases/customer-local/$VERSION"

section() {
  echo
  echo "===== $1 ====="
}

require_file() {
  local f="$1"
  test -f "$f" && echo "OK $f" || { echo "MISSING $f"; exit 1; }
}

require_dir() {
  local d="$1"
  test -d "$d" && echo "OK $d" || { echo "MISSING_DIR $d"; exit 1; }
}

json_get_token() {
  python3 - <<'PY'
import json
from pathlib import Path

p = Path("/tmp/gb_validate_fresh_login.json")
try:
    print(json.loads(p.read_text()).get("access_token", ""))
except Exception:
    print("")
PY
}

section "VALIDATE INPUTS"
echo "VERSION=$VERSION"
echo "EXPECTED_COMMIT=$EXPECTED_COMMIT"
echo "TENANT_CODE=$TENANT_CODE"
echo "EMAIL=$EMAIL"
echo "CONFIRM_DESTROY=$CONFIRM_DESTROY"

section "VALIDATE RELEASE ARTIFACTS"
require_file "$REL/BUILD-INFO.txt"
require_file "$REL/customer-local-$VERSION.tar.gz"
require_file "$REL/GreenBrain-Installer.zip"
grep -n "^release_version=$VERSION$" "$REL/BUILD-INFO.txt"
grep -n "^git_commit=$EXPECTED_COMMIT$" "$REL/BUILD-INFO.txt"

section "VALIDATE GHCR IMAGES EXIST LOCALLY OR REMOTELY"
docker pull "ghcr.io/giovannitoni/greenbrain-customer-backend:$VERSION"
docker pull "ghcr.io/giovannitoni/greenbrain-customer-ml-worker:$VERSION"
docker pull "ghcr.io/giovannitoni/greenbrain-customer-source-db-importer:$VERSION"

section "LOGIN CUSTOMER PORTAL"
curl --max-time 30 -sS -o /tmp/gb_validate_fresh_login.json -w 'HTTP=%{http_code}\n' \
  -X POST https://www.greenbrain.it/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\"}"

cat /tmp/gb_validate_fresh_login.json
echo

TOKEN="$(json_get_token)"
if [ -z "$TOKEN" ]; then
  echo "TOKEN_MISSING"
  exit 1
fi
echo "TOKEN_OK=yes"

section "DOWNLOAD PERSONALIZED BUNDLE"
DOWNLOAD_DIR="$(mktemp -d "/tmp/gb_validate_${VERSION//./_}_${TENANT_CODE}_download_XXXXXX")"
ZIP_OUT="$DOWNLOAD_DIR/GreenBrain-Installer-${VERSION}-${TENANT_CODE}.zip"

curl --connect-timeout 10 --max-time 180 --fail-with-body \
  -sS -D "$DOWNLOAD_DIR/headers.txt" \
  -o "$ZIP_OUT" \
  -w 'HTTP=%{http_code}\n' \
  -L \
  -H "Authorization: Bearer $TOKEN" \
  -H "Cache-Control: no-cache" \
  -H "Pragma: no-cache" \
  "https://www.greenbrain.it/api/v1/customer-portal/download-bundle?t=$(date +%s)"

sed -n '1,140p' "$DOWNLOAD_DIR/headers.txt"
file "$ZIP_OUT" || true
sha256sum "$ZIP_OUT"

section "FIND HOST-VISIBLE PERSONALIZED TAR"
LATEST_TAR="$(ls -t "$ROOT/runtime-reports/customer-bundles/customer-local-${VERSION}-${TENANT_CODE}-"*.tar.gz 2>/dev/null | head -1 || true)"
LATEST_ZIP="$(ls -t "$ROOT/runtime-reports/customer-bundles/GreenBrain-Installer-${VERSION}-${TENANT_CODE}-"*.zip 2>/dev/null | head -1 || true)"

echo "LATEST_TAR=$LATEST_TAR"
echo "LATEST_ZIP=$LATEST_ZIP"

require_file "$LATEST_TAR"
require_file "$LATEST_ZIP"

section "INSPECT PERSONALIZED TAR"
INSPECT_TMP="$(mktemp -d "/tmp/gb_validate_${VERSION//./_}_${TENANT_CODE}_inspect_XXXXXX")"
tar -xzf "$LATEST_TAR" -C "$INSPECT_TMP"
IPKG="$INSPECT_TMP/package/customer-local-template"
require_dir "$IPKG"

cat "$IPKG/VERSION"
grep -n "^package_version: $VERSION$" "$IPKG/release-manifest.yml"
grep -n "proxy_pass http://backend:8000;" "$IPKG/overlay/frontend-nginx/default.conf"
grep -nE '@router.post\("/password-sync/run-local"\)|cloud_unreachable|apply_cloud_password_sync' \
  "$IPKG/base/backend-src/app/api/v1/customer_runtime.py"

TOKEN_HINT="$(python3 - <<PY
from pathlib import Path
env = Path("$IPKG/overlay/provisioning/local-runtime.env")
token = ""
for line in env.read_text().splitlines():
    if line.startswith("PROVISIONING_TOKEN="):
        token = line.split("=", 1)[1].strip().strip('"').strip("'")
print(token[-6:] if token else "")
PY
)"
echo "TOKEN_HINT=$TOKEN_HINT"
test -n "$TOKEN_HINT" || { echo "TOKEN_HINT_MISSING"; exit 1; }

section "CLEAN STANDARD LOCAL TEST RUNTIME"
if docker ps -a --format '{{.Names}}' | grep -E '^(greenbrain_local_backend|greenbrain_local_frontend|greenbrain_local_postgres|greenbrain_local_ml_worker|greenbrain_local_source_db_importer|gb_customer_scheduler)$' >/dev/null; then
  TPL_ACTIVE="$(docker inspect greenbrain_local_frontend \
    --format '{{range .Mounts}}{{if eq .Destination "/usr/share/nginx/html"}}{{.Source}}{{end}}{{end}}' 2>/dev/null \
    | sed 's#/base/frontend-dist##' || true)"
  echo "TPL_ACTIVE=$TPL_ACTIVE"

  if [ -n "${TPL_ACTIVE:-}" ] && [ -d "$TPL_ACTIVE" ] && [ -f "$TPL_ACTIVE/overlay/env/customer-local.env" ]; then
    (
      cd "$TPL_ACTIVE"
      docker compose -f docker-compose.prebuilt.yml --env-file overlay/env/customer-local.env down -v --remove-orphans || true
      docker compose -f docker-compose.local.yml --env-file overlay/env/customer-local.env down -v --remove-orphans || true
    )
  fi
fi

docker rm -f \
  greenbrain_local_backend \
  greenbrain_local_frontend \
  greenbrain_local_postgres \
  greenbrain_local_ml_worker \
  greenbrain_local_source_db_importer \
  gb_customer_scheduler \
  2>/dev/null || true

docker volume ls --format '{{.Name}}' \
  | grep -E 'greenbrain_local_postgres_data|customer-local-template_greenbrain_local_postgres_data' \
  | xargs -r docker volume rm || true

section "INSTALL PERSONALIZED BUNDLE"
INSTALL_TMP="$(mktemp -d "/tmp/gb_validate_${VERSION//./_}_${TENANT_CODE}_install_XXXXXX")"
tar -xzf "$LATEST_TAR" -C "$INSTALL_TMP"
TPL="$INSTALL_TMP/package/customer-local-template"
require_dir "$TPL"

cd "$TPL"
GREENBRAIN_CONFIGURE_SOURCE_DB=no bash install.sh
INSTALL_RC=$?
echo "INSTALL_RC=$INSTALL_RC"

section "VALIDATE RUNNING RUNTIME"
cat VERSION
grep -n "^package_version: $VERSION$" release-manifest.yml
grep -n "proxy_pass http://backend:8000;" overlay/frontend-nginx/default.conf

docker compose -f docker-compose.prebuilt.yml --env-file overlay/env/customer-local.env ps
docker inspect greenbrain_local_backend --format 'BACKEND_IMAGE={{.Config.Image}}'
docker inspect greenbrain_local_ml_worker --format 'ML_IMAGE={{.Config.Image}}'
docker inspect greenbrain_local_source_db_importer --format 'SOURCE_DB_IMPORTER_IMAGE={{.Config.Image}}'

docker inspect greenbrain_local_backend --format '{{.Config.Image}}' | grep ":$VERSION$"
docker inspect greenbrain_local_ml_worker --format '{{.Config.Image}}' | grep ":$VERSION$"
docker inspect greenbrain_local_source_db_importer --format '{{.Config.Image}}' | grep ":$VERSION$"

section "VALIDATE ROUTES"
curl -sS -i http://localhost:8008/health | sed -n '1,80p'

curl -sS http://localhost:8008/openapi.json > /tmp/gb_validate_fresh_openapi.json
python3 - <<'PY'
import json
from pathlib import Path

data = json.loads(Path("/tmp/gb_validate_fresh_openapi.json").read_text())
paths = set(data.get("paths", {}).keys())
required = [
    "/api/v1/customer-runtime/password-sync/run-local",
    "/api/v1/customer-runtime/heartbeat",
    "/api/v1/customer-runtime/register",
]
for p in required:
    print(f"{p}: {'OK' if p in paths else 'MISSING'}")
    if p not in paths:
        raise SystemExit(f"MISSING {p}")
PY

echo "--- frontend proxy run-local"
curl -sS -i -X POST http://localhost:8088/api/v1/customer-runtime/password-sync/run-local | sed -n '1,200p'

echo "--- direct backend run-local"
curl -sS -i -X POST http://localhost:8008/api/v1/customer-runtime/password-sync/run-local | sed -n '1,200p'

section "VALIDATE LOCAL LOGIN"
curl -sS -o /tmp/gb_validate_fresh_local_login.json -w 'HTTP=%{http_code}\n' \
  -X POST http://localhost:8008/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\"}"

cat /tmp/gb_validate_fresh_local_login.json
echo
grep -q "access_token" /tmp/gb_validate_fresh_local_login.json || { echo "LOCAL_LOGIN_TOKEN_MISSING"; exit 1; }

section "RUN DOCTOR EXTENDED DAILY"
bash base/scripts/doctor-local.sh
bash base/scripts/doctor-local-extended.sh
bash base/scripts/run-local-daily-once.sh

section "FINAL RESULT"
echo "CUSTOMER_LOCAL_FRESH_INSTALL_VALIDATION_OK version=$VERSION tenant=$TENANT_CODE"
echo "TOKEN_HINT=$TOKEN_HINT"
echo "TPL=$TPL"
