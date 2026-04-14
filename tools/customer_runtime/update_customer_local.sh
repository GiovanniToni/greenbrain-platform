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

echo "== Backup =="
bash "$ROOT/deploy/customer-local-instances/$SLUG/base/scripts/pre-update-backup.sh"

echo
echo "== Update base dal template corrente =="
bash "$ROOT/tools/release/update_customer_instance_from_template.sh" "$SLUG"

echo
echo "== Validate =="
bash "$ROOT/tools/onboarding/validate_customer_local_instance.sh" "$SLUG"

echo
echo "== Restart =="
docker compose \
  --env-file "$ROOT/deploy/customer-local-instances/$SLUG/overlay/env/customer-local.env" \
  -f "$ROOT/deploy/customer-local-instances/$SLUG/docker-compose.local.yml" \
  up -d --build

echo
echo "Aggiornamento completato per: $SLUG"
echo "Nota: questo script oggi aggiorna dall'istanza/template locale, non ancora da un archivio consegnato al cliente."
