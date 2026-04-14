#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Uso:"
  echo "  update_customer_local.sh <release_version> <customer_instance_slug>"
  exit 1
fi

VERSION="$1"
SLUG="$2"
ROOT="/opt/greenbrain-platform"
INSTANCE="$ROOT/deploy/customer-local-instances/$SLUG"
ENV_FILE="$INSTANCE/overlay/env/customer-local.env"
COMPOSE_FILE="$INSTANCE/docker-compose.local.yml"

fail() {
  echo "ERRORE: $1" >&2
  exit 1
}

ok() {
  echo "OK: $1"
}

[ -d "$INSTANCE" ] || fail "Istanza non trovata: $INSTANCE"
[ -f "$ENV_FILE" ] || fail "Env file non trovato: $ENV_FILE"
[ -f "$COMPOSE_FILE" ] || fail "Compose file non trovato: $COMPOSE_FILE"

echo "== VALIDAZIONE PRE-UPDATE =="
bash "$ROOT/tools/onboarding/validate_customer_local_instance.sh" "$SLUG"

echo
echo "== BACKUP PRE-UPDATE =="
bash "$INSTANCE/base/scripts/pre-update-backup.sh"

echo
echo "== UPDATE BASE DAL TEMPLATE =="
bash "$ROOT/tools/release/update_customer_instance_from_template.sh" "$SLUG"

echo
echo "== VALIDAZIONE POST-SYNC =="
bash "$ROOT/tools/onboarding/validate_customer_local_instance.sh" "$SLUG"

echo
echo "== RESTART RUNTIME =="
docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  up -d --build

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

[ "$OK" -eq 1 ] || fail "backend non healthy dopo update"

echo
echo "== POST-UPDATE CHECK =="
bash "$INSTANCE/base/scripts/post-update-check.sh"

echo
ok "aggiornamento completato per: $SLUG"
echo "Nota: la variabile <release_version> oggi è informativa; il flusso aggiorna ancora dal template locale già presente sul server."
