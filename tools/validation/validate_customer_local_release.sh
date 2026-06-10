#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
EXPECTED_COMMIT="${2:-}"

if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version> [expected_git_commit]"
  echo "Example: $0 0.1.138 4eeb84945b3a6e3118bc9811ce09c084b93a993d"
  exit 2
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

grep_required() {
  local pattern="$1"
  local file="$2"
  grep -nE "$pattern" "$file" || { echo "PATTERN_NOT_FOUND pattern=$pattern file=$file"; exit 1; }
}

section "VALIDATE RELEASE DIRECTORY"
require_dir "$REL"
ls -lah "$REL"

section "VALIDATE RELEASE FILES"
require_file "$REL/BUILD-INFO.txt"
require_file "$REL/customer-local-$VERSION.tar.gz"
require_file "$REL/INSTALLA_GREENBRAIN.run"
require_file "$REL/GreenBrain-Installer.zip"

section "VALIDATE BUILD INFO"
cat "$REL/BUILD-INFO.txt"
grep_required "^release_version=$VERSION$" "$REL/BUILD-INFO.txt"

if [ -n "$EXPECTED_COMMIT" ]; then
  grep_required "^git_commit=$EXPECTED_COMMIT$" "$REL/BUILD-INFO.txt"
fi

section "EXTRACT TAR PAYLOAD"
TMP="$(mktemp -d "/tmp/gb_validate_${VERSION//./_}_tar_XXXXXX")"
tar -xzf "$REL/customer-local-$VERSION.tar.gz" -C "$TMP"
PKG="$TMP/package/customer-local-template"
require_dir "$PKG"
echo "PKG=$PKG"

section "VALIDATE TAR VERSION"
require_file "$PKG/VERSION"
require_file "$PKG/release-manifest.yml"
cat "$PKG/VERSION"
grep_required "^package_version: $VERSION$" "$PKG/release-manifest.yml"

section "VALIDATE TAR CORE FILES"
for f in \
  install.sh \
  docker-compose.prebuilt.yml \
  docker-compose.local.yml \
  overlay/frontend-nginx/default.conf \
  base/backend-src/app/api/v1/customer_runtime.py \
  base/backend-src/app/db/users.py \
  base/frontend-dist/index.html \
  base/frontend-dist/wizard_index.html
do
  require_file "$PKG/$f"
done

section "VALIDATE NGINX LOCAL PROXY"
grep_required "proxy_pass http://backend:8000;" "$PKG/overlay/frontend-nginx/default.conf"

if grep -RIn "proxy_pass http://host.docker.internal:8008;" "$PKG" >/tmp/gb_validate_old_proxy_matches.txt 2>/dev/null; then
  echo "ERROR_OLD_PROXY_TARGET_FOUND"
  cat /tmp/gb_validate_old_proxy_matches.txt
  exit 1
else
  echo "OK no old host.docker.internal:8008 proxy target"
fi

section "VALIDATE RUN-LOCAL BACKEND MARKERS"
grep_required "@router.post\\(\"/password-sync/run-local\"\\)" "$PKG/base/backend-src/app/api/v1/customer_runtime.py"
grep_required "def run_local_password_sync_route" "$PKG/base/backend-src/app/api/v1/customer_runtime.py"
grep_required "apply_cloud_password_sync" "$PKG/base/backend-src/app/api/v1/customer_runtime.py"
grep_required "cloud_unreachable" "$PKG/base/backend-src/app/api/v1/customer_runtime.py"
grep_required "pending_http_status.: 0" "$PKG/base/backend-src/app/api/v1/customer_runtime.py"

section "VALIDATE LOCAL PASSWORD SYNC DB MARKERS"
grep_required "def ensure_password_sync_schema" "$PKG/base/backend-src/app/db/users.py"
grep_required "def apply_cloud_password_sync" "$PKG/base/backend-src/app/db/users.py"
grep_required "password_synced_from_cloud" "$PKG/base/backend-src/app/db/users.py"

section "VALIDATE FRONTEND MARKERS"
grep -RohE \
  "local-sync/password|Sincronizzazione password|Sincronizza GreenBrain locale ora|/api/v1/customer-runtime/password-sync/run-local|/api/v1/customer-portal/download-bundle" \
  "$PKG/base/frontend-dist" \
  | sort -u

for marker in \
  "local-sync/password" \
  "Sincronizzazione password" \
  "Sincronizza GreenBrain locale ora" \
  "/api/v1/customer-runtime/password-sync/run-local" \
  "/api/v1/customer-portal/download-bundle"
do
  if grep -R "$marker" "$PKG/base/frontend-dist" >/dev/null 2>&1; then
    echo "OK frontend marker: $marker"
  else
    echo "MISSING_FRONTEND_MARKER: $marker"
    exit 1
  fi
done

section "VALIDATE PREBUILT COMPOSE"
if grep -RIn "build:" "$PKG/docker-compose.prebuilt.yml"; then
  echo "ERROR_PREBUILT_COMPOSE_HAS_BUILD"
  exit 1
else
  echo "OK docker-compose.prebuilt.yml has no build sections"
fi

grep_required "ghcr.io/giovannitoni/greenbrain-customer-backend" "$PKG/docker-compose.prebuilt.yml"
grep_required "ghcr.io/giovannitoni/greenbrain-customer-ml-worker" "$PKG/docker-compose.prebuilt.yml"
grep_required "ghcr.io/giovannitoni/greenbrain-customer-source-db-importer" "$PKG/docker-compose.prebuilt.yml"
grep_required "GREENBRAIN_IMAGE_TAG" "$PKG/docker-compose.prebuilt.yml"

section "VALIDATE UNIVERSAL ZIP STRUCTURE"
ZIPTMP="$(mktemp -d "/tmp/gb_validate_${VERSION//./_}_zip_XXXXXX")"
unzip -q "$REL/GreenBrain-Installer.zip" -d "$ZIPTMP"

for f in \
  INSTALLA_GREENBRAIN_LINUX.run \
  INSTALLA_GREENBRAIN_MAC.command \
  INSTALLA_GREENBRAIN_WINDOWS.bat \
  INSTALLA_GREENBRAIN_WINDOWS.ps1 \
  LEGGIMI_INSTALLAZIONE.txt
do
  require_file "$ZIPTMP/$f"
done

section "VALIDATE ZIP EMBEDDED PAYLOAD"
RUN="$ZIPTMP/INSTALLA_GREENBRAIN_LINUX.run"
ARCHIVE_LINE="$(awk '/^__GREENBRAIN_ARCHIVE_BELOW__$/ {print NR + 1; exit 0;}' "$RUN")"
test -n "$ARCHIVE_LINE" || { echo "ARCHIVE_MARKER_MISSING"; exit 1; }
echo "ARCHIVE_LINE=$ARCHIVE_LINE"

PAYLOAD_TMP="$(mktemp -d "/tmp/gb_validate_${VERSION//./_}_zip_payload_XXXXXX")"
tail -n +"$ARCHIVE_LINE" "$RUN" | tar -xzf - -C "$PAYLOAD_TMP"
ZPKG="$PAYLOAD_TMP/package/customer-local-template"
require_dir "$ZPKG"

cat "$ZPKG/VERSION"
grep_required "^package_version: $VERSION$" "$ZPKG/release-manifest.yml"
grep_required "proxy_pass http://backend:8000;" "$ZPKG/overlay/frontend-nginx/default.conf"
grep_required "@router.post\\(\"/password-sync/run-local\"\\)" "$ZPKG/base/backend-src/app/api/v1/customer_runtime.py"
grep_required "cloud_unreachable" "$ZPKG/base/backend-src/app/api/v1/customer_runtime.py"

if grep -RIn "proxy_pass http://host.docker.internal:8008;" "$ZPKG" >/tmp/gb_validate_zip_old_proxy_matches.txt 2>/dev/null; then
  echo "ERROR_OLD_PROXY_TARGET_FOUND_IN_ZIP_PAYLOAD"
  cat /tmp/gb_validate_zip_old_proxy_matches.txt
  exit 1
else
  echo "OK no old host.docker.internal:8008 proxy target in ZIP payload"
fi

section "FINAL RESULT"
echo "CUSTOMER_LOCAL_RELEASE_STATIC_VALIDATION_OK version=$VERSION"
