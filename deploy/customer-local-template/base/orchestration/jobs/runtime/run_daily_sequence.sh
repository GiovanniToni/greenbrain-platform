#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/orchestration/lib/common.sh"

gb_load_env

LOG="$GB_LOG_DIR/daily_sequence_$(date +%Y%m%d_%H%M%S).log"
ln -sfn "$LOG" "$GB_LOG_DIR/daily_sequence_latest.log"

{
  gb_log "GREENBRAIN_LOCAL_DAILY_SEQUENCE_START"

  gb_log "STEP 1 pipeline"
  bash "$ROOT/orchestration/jobs/pipeline/run_daily_pipeline.sh"

  gb_log "STEP 2 ml placeholder"
  echo "ML local orchestration not enabled yet in 0.1.27 skeleton"

  gb_log "STEP 3 heartbeat"
  bash "$GB_LOCAL_ROOT/base/scripts/runtime-heartbeat.sh" || true

  gb_log "GREENBRAIN_LOCAL_DAILY_SEQUENCE_DONE"
} 2>&1 | tee -a "$LOG"
