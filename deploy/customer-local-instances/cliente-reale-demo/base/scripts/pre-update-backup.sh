#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if [ -f "$BASE_DIR/overlay/env/customer-local.env" ]; then
  ENV_FILE="$BASE_DIR/overlay/env/customer-local.env"
elif [ -f "$BASE_DIR/env/customer-local.env" ]; then
  ENV_FILE="$BASE_DIR/env/customer-local.env"
else
  echo "Manca customer-local.env in overlay/env o env"
  exit 1
fi

if [ -f "$BASE_DIR/docker-compose.local.yml" ]; then
  COMPOSE_FILE="$BASE_DIR/docker-compose.local.yml"
else
  echo "Manca $BASE_DIR/docker-compose.local.yml"
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTDIR="$BASE_DIR/backups/pre-update-$STAMP"

mkdir -p "$OUTDIR"

cp "$COMPOSE_FILE" "$OUTDIR/docker-compose.local.yml"

if [ -d "$BASE_DIR/overlay" ]; then
  mkdir -p "$OUTDIR/overlay"
  cp -R "$BASE_DIR/overlay/." "$OUTDIR/overlay/"
fi

if [ -d "$BASE_DIR/env" ]; then
  mkdir -p "$OUTDIR/env"
  cp -R "$BASE_DIR/env/." "$OUTDIR/env/"
fi

if [ -f "$BASE_DIR/VERSION" ]; then
  cp "$BASE_DIR/VERSION" "$OUTDIR/VERSION"
fi

if [ -f "$BASE_DIR/release-manifest.yml" ]; then
  cp "$BASE_DIR/release-manifest.yml" "$OUTDIR/release-manifest.yml"
fi

POSTGRES_CID="$(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps -q postgres 2>/dev/null || true)"

if [ -z "$POSTGRES_CID" ]; then
  echo "WARN: container postgres non attivo per questa istanza; dump DB saltato" | tee "$OUTDIR/backup-warning.txt"
else
  TMP_DUMP="$OUTDIR/local-db.sql.tmp"
  rm -f "$TMP_DUMP"

  if docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres \
    sh -lc 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
    > "$TMP_DUMP"; then
    mv "$TMP_DUMP" "$OUTDIR/local-db.sql"
    echo "Dump DB eseguito via service postgres"
  else
    rm -f "$TMP_DUMP"
    echo "ERRORE: dump DB fallito sul service postgres"
    exit 1
  fi
fi

echo "Backup creato in: $OUTDIR"
