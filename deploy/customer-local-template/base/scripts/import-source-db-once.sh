#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV="$ROOT/overlay/env/customer-local.env"
SOURCE_ENV="$ROOT/overlay/env/source-db.env"

echo "== GreenBrain Source DB Import Once =="

mkdir -p "$ROOT/overlay/logs/source-db"
TS="$(date -u +%Y%m%d_%H%M%S)"
LOG="$ROOT/overlay/logs/source-db/import_sales_raw_${TS}.log"
LATEST="$ROOT/overlay/logs/source-db/import_sales_raw_latest.log"

if [ ! -f "$SOURCE_ENV" ]; then
  echo "source-db.env not configured, skipping import" | tee "$LOG"
  ln -sfn "$(basename "$LOG")" "$LATEST"
  exit 0
fi

if ! bash "$ROOT/base/scripts/test-source-db-connection.sh" 2>&1 | tee -a "$LOG"; then
  echo "SOURCE_DB_IMPORT_SKIPPED_UNREACHABLE" | tee -a "$LOG"
  ln -sfn "$(basename "$LOG")" "$LATEST"
  exit 2
fi

set +e
if command -v docker >/dev/null 2>&1; then
  docker compose -f "$ROOT/docker-compose.local.yml" --env-file "$ENV" run --rm ml-worker \
    bash -lc 'cd /workspace && python base/apps/source-db-importer/import_sales_raw.py' 2>&1 | tee "$LOG"
else
  cd "$ROOT"
  python base/apps/source-db-importer/import_sales_raw.py 2>&1 | tee "$LOG"
fi
RC="${PIPESTATUS[0]}"
set -e

ln -sfn "$(basename "$LOG")" "$LATEST"

if [ "$RC" -ne 0 ]; then
  echo "SOURCE_DB_IMPORT_ONCE_FAILED rc=$RC"
  exit "$RC"
fi

echo "SOURCE_DB_IMPORT_ONCE_OK"
