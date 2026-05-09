#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV="$ROOT/overlay/env/customer-local.env"
INIT_DIR="$ROOT/base/client-runtime/sql/init"

[ -f "$ENV" ] || { echo "ERROR: missing $ENV"; exit 1; }

set -a
source "$ENV"
set +a

echo "== Applying local SQL patches =="

for f in "$INIT_DIR"/2[5-9]_*.sql "$INIT_DIR"/[3-9][0-9]_*.sql; do
  [ -f "$f" ] || continue
  echo
  echo "----- $(basename "$f") -----"
  docker compose -f "$ROOT/docker-compose.local.yml" --env-file "$ENV" exec -T postgres \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -f "/docker-entrypoint-initdb.d/$(basename "$f")"
done

echo
echo "SQL_PATCHES_OK"
