#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Uso:"
  echo "  promote_dev_to_customer_template.sh <version>"
  exit 1
fi

VERSION="$1"
ROOT="/opt/greenbrain-platform"
TEMPLATE="$ROOT/deploy/customer-local-template"
BACKEND_SRC="$ROOT/apps/backend"
FRONTEND_SRC="$ROOT/apps/frontend"
TEMPLATE_BASE="$TEMPLATE/base"

fail() {
  echo "ERRORE: $1" >&2
  exit 1
}

ok() {
  echo "OK: $1"
}

[ -d "$TEMPLATE" ] || fail "Template non trovato: $TEMPLATE"
[ -d "$BACKEND_SRC" ] || fail "Backend sorgente non trovato: $BACKEND_SRC"
[ -d "$FRONTEND_SRC" ] || fail "Frontend sorgente non trovato: $FRONTEND_SRC"
[ -d "$TEMPLATE_BASE" ] || fail "Base template non trovata: $TEMPLATE_BASE"

echo "== STEP 1: aggiorna versioning template =="
printf '%s\n' "$VERSION" > "$TEMPLATE/VERSION"

python3 - <<PY2
from pathlib import Path
import re

p = Path("$TEMPLATE/release-manifest.yml")
if not p.exists():
    raise SystemExit("release-manifest.yml non trovato")

s = p.read_text()
s2 = re.sub(r'^package_version:.*$', f'package_version: {"$VERSION"}', s, flags=re.M)

if s == s2 and "package_version:" not in s:
    raise SystemExit("package_version non trovato nel release-manifest.yml")

p.write_text(s2)
print("UPDATED", p)
PY2

echo
echo "== STEP 2: build frontend se necessario =="
if [ ! -f "$FRONTEND_SRC/dist/index.html" ]; then
  echo "Frontend dist assente: build obbligatoria"
  cd "$FRONTEND_SRC"
  npm run build
else
  if find "$FRONTEND_SRC/src" "$FRONTEND_SRC/public" -type f -newer "$FRONTEND_SRC/dist/index.html" 2>/dev/null | grep -q .; then
    echo "Sorgenti frontend più recenti della dist: rebuild"
    cd "$FRONTEND_SRC"
    npm run build
  else
    echo "Frontend dist già aggiornata: skip build"
  fi
fi

echo
echo "== STEP 3: sync backend dev -> template base =="
mkdir -p "$TEMPLATE_BASE/backend-src"

rsync -a --delete \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  --exclude '.env' \
  --exclude '.pytest_cache/' \
  --exclude '.mypy_cache/' \
  "$BACKEND_SRC/" "$TEMPLATE_BASE/backend-src/"

ok "backend template aggiornato"

echo
echo "== STEP 4: sync frontend dist -> template base =="
mkdir -p "$TEMPLATE_BASE/frontend-dist"

rsync -a --delete \
  "$FRONTEND_SRC/dist/" "$TEMPLATE_BASE/frontend-dist/"

ok "frontend template aggiornato"

echo
echo "== STEP 5: validazione template =="
[ -f "$TEMPLATE/docker-compose.local.yml" ] || fail "docker-compose.local.yml template mancante"
[ -f "$TEMPLATE/tunnel/docker-compose.tunnel.yml" ] || fail "tunnel/docker-compose.tunnel.yml template mancante"
[ -f "$TEMPLATE/base/base-manifest.yml" ] || fail "base/base-manifest.yml template mancante"
[ -f "$TEMPLATE/overlay/meta/overlay-manifest.yml" ] || fail "overlay/meta/overlay-manifest.yml template mancante"
[ -f "$TEMPLATE/overlay/env/customer-local.env" ] || fail "overlay/env/customer-local.env template mancante"
[ -f "$TEMPLATE/overlay/tunnel/cloudflared/cloudflared.env" ] || fail "overlay tunnel env template mancante"

docker compose \
  --env-file "$TEMPLATE/overlay/env/customer-local.env" \
  -f "$TEMPLATE/docker-compose.local.yml" \
  config >/dev/null

docker compose \
  -f "$TEMPLATE/tunnel/docker-compose.tunnel.yml" \
  config >/dev/null

ok "compose template validi"

echo
echo "== STEP 6: verifica coerenza versioni =="
TV="$(cat "$TEMPLATE/VERSION")"
MV="$(awk -F': ' '/^package_version:/{print $2}' "$TEMPLATE/release-manifest.yml")"

[ "$TV" = "$VERSION" ] || fail "VERSION template non coerente"
[ "$MV" = "$VERSION" ] || fail "package_version template non coerente"

ok "versioning template coerente: $VERSION"

echo
echo "Promozione dev -> customer template completata con successo"
echo "Template aggiornato a versione: $VERSION"
