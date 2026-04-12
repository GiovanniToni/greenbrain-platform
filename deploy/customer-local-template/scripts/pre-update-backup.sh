#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$BASE_DIR/env/customer-local.env"

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

cp "$ENV_FILE" "$OUTDIR/customer-local.env"
cp "$BASE_DIR/docker-compose.local.yml" "$OUTDIR/docker-compose.local.yml"

if [ -f "$BASE_DIR/frontend-nginx/default.conf" ]; then
  cp "$BASE_DIR/frontend-nginx/default.conf" "$OUTDIR/frontend-nginx.default.conf"
fi

if [ -d "$BASE_DIR/tunnel/cloudflared" ]; then
  mkdir -p "$OUTDIR/tunnel-cloudflared"
  cp -R "$BASE_DIR/tunnel/cloudflared/." "$OUTDIR/tunnel-cloudflared/" || true
fi

docker exec -i greenbrain_local_postgres \
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  > "$OUTDIR/local-db.sql"

echo "Backup creato in: $OUTDIR"
