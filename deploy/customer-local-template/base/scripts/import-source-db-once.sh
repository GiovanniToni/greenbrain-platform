#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV="$ROOT/overlay/env/customer-local.env"
SOURCE_ENV="$ROOT/overlay/env/source-db.env"

echo "== GreenBrain Source DB Import Once =="

if [ ! -f "$SOURCE_ENV" ]; then
  echo "source-db.env not configured, skipping import"
  exit 0
fi

docker compose -f "$ROOT/docker-compose.local.yml" --env-file "$ENV" run --rm ml-worker \
  bash -lc 'cd /workspace && python base/apps/source-db-importer/import_sales_raw.py'

echo "SOURCE_DB_IMPORT_ONCE_OK"
