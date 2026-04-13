#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Uso:"
  echo "  release_customer_local.sh <version> <customer_instance_slug>"
  exit 1
fi

VERSION="$1"
SLUG="$2"

ROOT="/opt/greenbrain-platform"
INSTANCE="$ROOT/deploy/customer-local-instances/$SLUG"
ENV_FILE="$INSTANCE/overlay/env/customer-local.env"

if [ ! -d "$INSTANCE" ]; then
  echo "Istanza non trovata: $INSTANCE"
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "Env overlay non trovato: $ENV_FILE"
  exit 1
fi

echo "== STEP 1: build release =="
if [ -d "$ROOT/releases/customer-local/$VERSION" ]; then
  echo "Release $VERSION già esistente: skip build"
else
  bash "$ROOT/tools/release/build_customer_local_release.sh" "$VERSION"
fi

echo
echo "== STEP 2: backup instance =="
bash "$INSTANCE/base/scripts/pre-update-backup.sh"

echo
echo "== STEP 3: sync template -> instance =="
bash "$ROOT/tools/release/update_customer_instance_from_template.sh" "$SLUG"

echo
echo "== STEP 4: restart local runtime =="
docker compose \
  --env-file "$ENV_FILE" \
  -f "$INSTANCE/docker-compose.local.yml" \
  up -d --build

echo
echo "== STEP 5: wait backend healthy =="
OK=0
for i in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:8008/health" >/dev/null 2>&1; then
    echo "Backend healthy"
    OK=1
    break
  fi
  sleep 2
done

if [ "$OK" -ne 1 ]; then
  echo "Backend non healthy entro timeout"
  exit 1
fi

echo
echo "== STEP 6: post-update checks =="
bash "$INSTANCE/base/scripts/post-update-check.sh"

echo
echo "Release applicata con successo a: $SLUG"
