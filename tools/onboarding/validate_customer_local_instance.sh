#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Uso:"
  echo "  validate_customer_local_instance.sh <customer_instance_slug>"
  exit 1
fi

SLUG="$1"
ROOT="/opt/greenbrain-platform"
INSTANCE="$ROOT/deploy/customer-local-instances/$SLUG"

if [ ! -d "$INSTANCE" ]; then
  echo "Istanza non trovata: $INSTANCE"
  exit 1
fi

fail() {
  echo "ERRORE: $1" >&2
  exit 1
}

ok() {
  echo "OK: $1"
}

echo "== VALIDAZIONE STRUTTURA =="
[ -f "$INSTANCE/docker-compose.local.yml" ] || fail "docker-compose.local.yml mancante"
[ -f "$INSTANCE/tunnel/docker-compose.tunnel.yml" ] || fail "tunnel/docker-compose.tunnel.yml mancante"
[ -f "$INSTANCE/VERSION" ] || fail "VERSION mancante"
[ -f "$INSTANCE/release-manifest.yml" ] || fail "release-manifest.yml mancante"
[ -f "$INSTANCE/base/base-manifest.yml" ] || fail "base/base-manifest.yml mancante"
[ -f "$INSTANCE/overlay/meta/overlay-manifest.yml" ] || fail "overlay/meta/overlay-manifest.yml mancante"
[ -f "$INSTANCE/overlay/env/customer-local.env" ] || fail "overlay/env/customer-local.env mancante"
[ -f "$INSTANCE/overlay/frontend-nginx/default.conf" ] || fail "overlay/frontend-nginx/default.conf mancante"
[ -f "$INSTANCE/overlay/tunnel/cloudflared/config.yml" ] || fail "overlay tunnel config.yml mancante"
[ -f "$INSTANCE/overlay/tunnel/cloudflared/cloudflared.env" ] || fail "overlay tunnel cloudflared.env mancante"
ok "struttura base/overlay presente"

echo
echo "== VALIDAZIONE COMPOSE =="
docker compose \
  --env-file "$INSTANCE/overlay/env/customer-local.env" \
  -f "$INSTANCE/docker-compose.local.yml" \
  config >/dev/null || fail "docker compose locale non valido"

docker compose \
  -f "$INSTANCE/tunnel/docker-compose.tunnel.yml" \
  config >/dev/null || fail "docker compose tunnel non valido"

ok "compose locale e tunnel validi"

echo
echo "== LETTURA ENV =="
set -a
source "$INSTANCE/overlay/env/customer-local.env"
set +a

[ -n "${TENANT_CODE:-}" ] || fail "TENANT_CODE vuoto"
[ -n "${TENANT_HOST:-}" ] || fail "TENANT_HOST vuoto"
[ -n "${POSTGRES_DB:-}" ] || fail "POSTGRES_DB vuoto"
[ -n "${POSTGRES_USER:-}" ] || fail "POSTGRES_USER vuoto"
[ -n "${LOCAL_BACKEND_PORT:-}" ] || fail "LOCAL_BACKEND_PORT vuoto"
[ -n "${LOCAL_FRONTEND_PORT:-}" ] || fail "LOCAL_FRONTEND_PORT vuoto"
ok "env leggibile"

echo
echo "== COERENZA TENANT HOST =="
grep -q "^TENANT_CODE=${TENANT_CODE}$" "$INSTANCE/overlay/env/customer-local.env" || fail "TENANT_CODE non coerente"
grep -q "^TENANT_HOST=${TENANT_HOST}$" "$INSTANCE/overlay/env/customer-local.env" || fail "TENANT_HOST non coerente"
grep -q "^TUNNEL_PUBLIC_HOST=${TENANT_HOST}$" "$INSTANCE/overlay/env/customer-local.env" || fail "TUNNEL_PUBLIC_HOST env non coerente"
grep -q "${TENANT_HOST}" "$INSTANCE/overlay/tunnel/cloudflared/config.yml" || fail "TENANT_HOST assente in config.yml tunnel"
grep -q "${TENANT_HOST}" "$INSTANCE/overlay/tunnel/cloudflared/cloudflared.env" || fail "TENANT_HOST assente in cloudflared.env"
ok "host tenant coerente tra env e tunnel"

echo
echo "== PLACEHOLDER / SEGRETI =="
if find "$INSTANCE/overlay" -type f ! -name '*.example' -print0 | xargs -0 grep -n "REPLACE_WITH_REAL_TUNNEL_UUID" >/dev/null 2>&1; then
  echo "WARN: tunnel UUID placeholder ancora presente"
else
  ok "nessun placeholder tunnel UUID"
fi

if find "$INSTANCE/overlay" -type f ! -name '*.example' -print0 | xargs -0 grep -n "CHANGE_ME" >/dev/null 2>&1; then
  echo "WARN: ci sono ancora valori CHANGE_ME nell'overlay"
else
  ok "nessun CHANGE_ME nell'overlay"
fi

echo
echo "== IGIENE BASE =="
if find "$INSTANCE/base" \( -type d -name '__pycache__' -o -type f -name '*.pyc' -o -type f -name '.env' \) | grep -q .; then
  fail "trovati artefatti sporchi in base (__pycache__, .pyc o .env)"
fi
ok "base pulita"

echo
echo "== VERSIONING =="
BASE_VERSION="$(cat "$INSTANCE/VERSION")"
MANIFEST_VERSION="$(grep '^package_version:' "$INSTANCE/release-manifest.yml" | awk '{print $2}')"

[ -n "$BASE_VERSION" ] || fail "VERSION vuota"
[ -n "$MANIFEST_VERSION" ] || fail "package_version mancante"
[ "$BASE_VERSION" = "$MANIFEST_VERSION" ] || fail "VERSION e package_version non coincidono"

ok "versioning coerente: $BASE_VERSION"

echo
echo "Validazione completata con successo per: $SLUG"
