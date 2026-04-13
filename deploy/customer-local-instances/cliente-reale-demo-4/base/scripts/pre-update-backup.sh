#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="$BASE_DIR/overlay/env/customer-local.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Manca $ENV_FILE"
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTDIR="$BASE_DIR/backups/pre-update-$STAMP"

mkdir -p "$OUTDIR"

cp "$BASE_DIR/docker-compose.local.yml" "$OUTDIR/docker-compose.local.yml"

if [ -d "$BASE_DIR/overlay" ]; then
  mkdir -p "$OUTDIR/overlay"
  cp -R "$BASE_DIR/overlay/." "$OUTDIR/overlay/"
fi

if [ -f "$BASE_DIR/VERSION" ]; then
  cp "$BASE_DIR/VERSION" "$OUTDIR/VERSION"
fi

if [ -f "$BASE_DIR/release-manifest.yml" ]; then
  cp "$BASE_DIR/release-manifest.yml" "$OUTDIR/release-manifest.yml"
fi

docker exec -i greenbrain_local_postgres \
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  > "$OUTDIR/local-db.sql"

echo "Backup creato in: $OUTDIR"
