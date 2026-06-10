#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV="$ROOT/overlay/env/customer-local.env"

mkdir -p "$ROOT/overlay/logs/source-db"
TS="$(date -u +%Y%m%d_%H%M%S)"
LOG="$ROOT/overlay/logs/source-db/technical_check_${TS}.log"
LATEST="$ROOT/overlay/logs/source-db/technical_check_latest.log"

echo "== GreenBrain Source DB Technical Check ==" | tee "$LOG"

set +e
if command -v docker >/dev/null 2>&1; then
  COMPOSE_FILE="$ROOT/docker-compose.local.yml"
  if [ -f "$ROOT/docker-compose.prebuilt.yml" ]; then
    COMPOSE_FILE="$ROOT/docker-compose.prebuilt.yml"
  fi

  docker compose -f "$COMPOSE_FILE" --env-file "$ENV" run --rm --no-deps source-db-importer \
    bash -lc 'cd /workspace && python base/apps/source-db-importer/technical_check_source_db.py' 2>&1 | tee -a "$LOG"
else
  cd "$ROOT"
  python3 base/apps/source-db-importer/technical_check_source_db.py 2>&1 | tee -a "$LOG"
fi
RC="${PIPESTATUS[0]}"
set -e

ln -sfn "$(basename "$LOG")" "$LATEST"

UPLOAD_SCRIPT="$ROOT/base/scripts/upload-source-db-technical-report.sh"
if [ -f "$UPLOAD_SCRIPT" ]; then
  set +e
  bash "$UPLOAD_SCRIPT" 2>&1 | tee -a "$LOG"
  UPLOAD_RC="${PIPESTATUS[0]}"
  set -e
  if [ "$UPLOAD_RC" -eq 0 ]; then
    echo "SOURCE_DB_TECHNICAL_REPORT_UPLOAD_NON_BLOCKING_OK" | tee -a "$LOG"
  else
    echo "SOURCE_DB_TECHNICAL_REPORT_UPLOAD_NON_BLOCKING_FAILED rc=$UPLOAD_RC" | tee -a "$LOG"
  fi
else
  echo "SOURCE_DB_TECHNICAL_REPORT_UPLOAD_SKIPPED missing_upload_script:$UPLOAD_SCRIPT" | tee -a "$LOG"
fi

if [ "$RC" -eq 0 ]; then
  echo "SOURCE_DB_TECHNICAL_CHECK_OK" | tee -a "$LOG"
  exit 0
fi

echo "SOURCE_DB_TECHNICAL_CHECK_FAILED rc=$RC" | tee -a "$LOG"
exit "$RC"
