#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Uso:"
  echo "  update_customer_local_from_bundle.sh <bundle_dir> <customer_instance_dir>"
  exit 1
fi

BUNDLE_DIR="$1"
INSTANCE_DIR="$2"
ENV_FILE="$INSTANCE_DIR/overlay/env/customer-local.env"
COMPOSE_FILE="$INSTANCE_DIR/docker-compose.local.yml"

fail() {
  echo "ERRORE: $1" >&2
  exit 1
}

ok() {
  echo "OK: $1"
}

[ -d "$BUNDLE_DIR" ] || fail "Bundle dir non trovata: $BUNDLE_DIR"
[ -d "$INSTANCE_DIR" ] || fail "Istanza non trovata: $INSTANCE_DIR"
[ -f "$ENV_FILE" ] || fail "Env file istanza non trovato: $ENV_FILE"
[ -f "$COMPOSE_FILE" ] || fail "Compose file istanza non trovato: $COMPOSE_FILE"

[ -d "$BUNDLE_DIR/base" ] || fail "Bundle non valido: manca base/"
[ -f "$BUNDLE_DIR/VERSION" ] || fail "Bundle non valido: manca VERSION"
[ -f "$BUNDLE_DIR/release-manifest.yml" ] || fail "Bundle non valido: manca release-manifest.yml"
[ -f "$BUNDLE_DIR/docker-compose.local.yml" ] || fail "Bundle non valido: manca docker-compose.local.yml"
[ -f "$BUNDLE_DIR/README.md" ] || fail "Bundle non valido: manca README.md"
[ -f "$BUNDLE_DIR/base-overlay-model.md" ] || fail "Bundle non valido: manca base-overlay-model.md"

echo "== BACKUP PRE-UPDATE =="
bash "$INSTANCE_DIR/base/scripts/pre-update-backup.sh"

echo
echo "== SYNC BASE DAL BUNDLE =="
mkdir -p "$INSTANCE_DIR/base"
rsync -a --delete "$BUNDLE_DIR/base/" "$INSTANCE_DIR/base/"

echo
echo "== UPDATE ROOT FILES =="
cp "$BUNDLE_DIR/docker-compose.local.yml" "$INSTANCE_DIR/docker-compose.local.yml"
cp "$BUNDLE_DIR/README.md" "$INSTANCE_DIR/README.md"
cp "$BUNDLE_DIR/VERSION" "$INSTANCE_DIR/VERSION"
cp "$BUNDLE_DIR/release-manifest.yml" "$INSTANCE_DIR/release-manifest.yml"
cp "$BUNDLE_DIR/base-overlay-model.md" "$INSTANCE_DIR/base-overlay-model.md"
cp "$BUNDLE_DIR/tunnel/docker-compose.tunnel.yml" "$INSTANCE_DIR/tunnel/docker-compose.tunnel.yml"

echo
echo "== UPDATE TEMPLATE FILES NON SENSIBILI =="
if [ -f "$BUNDLE_DIR/overlay/frontend-nginx/default.conf" ]; then
  cp "$BUNDLE_DIR/overlay/frontend-nginx/default.conf" \
     "$INSTANCE_DIR/overlay/frontend-nginx/default.conf.template"
fi

if [ -f "$BUNDLE_DIR/overlay/tunnel/cloudflared/config.yml.example" ]; then
  cp "$BUNDLE_DIR/overlay/tunnel/cloudflared/config.yml.example" \
     "$INSTANCE_DIR/overlay/tunnel/cloudflared/config.yml.example"
fi

if [ -f "$BUNDLE_DIR/overlay/tunnel/cloudflared/cloudflared.env.example" ]; then
  cp "$BUNDLE_DIR/overlay/tunnel/cloudflared/cloudflared.env.example" \
     "$INSTANCE_DIR/overlay/tunnel/cloudflared/cloudflared.env.example"
fi

echo
echo "== VALIDAZIONE PRE-RESTART =="
docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  config >/dev/null || fail "docker compose locale non valido dopo update"

echo
echo "== RESTART =="
docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  up -d --build

echo
echo "== APPLY LOCAL SQL PATCHES =="
if [ -x "$INSTANCE_DIR/base/scripts/apply-local-sql-patches.sh" ]; then
  bash "$INSTANCE_DIR/base/scripts/apply-local-sql-patches.sh"
else
  echo "No local SQL patch runner found, skipping."
fi

echo
echo "== HEALTH CHECK =="
set -a
source "$ENV_FILE"
set +a

OK=0
for i in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${LOCAL_BACKEND_PORT:-8008}/health" >/dev/null 2>&1; then
    echo "Backend healthy"
    OK=1
    break
  fi
  sleep 2
done

[ "$OK" -eq 1 ] || fail "backend non healthy dopo update da bundle"

echo
ok "aggiornamento completato da bundle"
