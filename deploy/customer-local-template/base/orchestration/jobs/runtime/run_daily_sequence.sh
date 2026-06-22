#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/orchestration/lib/common.sh"

gb_load_env

LOG="$GB_LOG_DIR/daily_sequence_$(date +%Y%m%d_%H%M%S).log"
ln -sfn "$(basename "$LOG")" "$GB_LOG_DIR/daily_sequence_latest.log"

{
  gb_log "GREENBRAIN_LOCAL_DAILY_SEQUENCE_START"

  gb_log "STEP 0 source db import"
  if bash "$GB_LOCAL_ROOT/base/scripts/import-source-db-once.sh"; then
    gb_log "SOURCE_DB_IMPORT_OK"
  else
    RC=$?
    if [ "$RC" = "2" ]; then
      gb_log "SOURCE_DB_IMPORT_SKIPPED_UNREACHABLE"
    elif [ "$RC" = "3" ]; then
      gb_log "SOURCE_DB_IMPORT_NOT_CONFIGURED"
    else
      gb_log "SOURCE_DB_IMPORT_FAILED_NON_BLOCKING"
    fi
  fi

  gb_log "STEP 0b source db raw promotion"
  if bash "$GB_LOCAL_ROOT/base/scripts/promote-source-db-raw.sh"; then
    gb_log "SOURCE_DB_RAW_PROMOTION_OK"
  else
    gb_log "SOURCE_DB_RAW_PROMOTION_FAILED_NON_BLOCKING"
  fi

  gb_log "STEP 0c source db data readiness"
  bash "$GB_LOCAL_ROOT/base/scripts/check-source-db-data-readiness.sh" || true

  gb_log "STEP 1 pipeline"
  bash "$ROOT/orchestration/jobs/pipeline/run_daily_pipeline.sh"

  gb_log "STEP 2 train missing"
  bash "$ROOT/orchestration/jobs/ml/run_train_missing_local.sh" || true

  gb_log "STEP 3 predict all"
  bash "$ROOT/orchestration/jobs/ml/run_predict_all_local.sh" || true

  gb_log "STEP 4 heartbeat"
  bash "$GB_LOCAL_ROOT/base/scripts/runtime-heartbeat.sh" || true

  gb_log "GREENBRAIN_LOCAL_DAILY_SEQUENCE_DONE"
} 2>&1 | tee -a "$LOG"
