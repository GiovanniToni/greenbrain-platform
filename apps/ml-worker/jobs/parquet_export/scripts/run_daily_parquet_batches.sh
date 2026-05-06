#!/bin/bash
set -Eeuo pipefail

export APP_ENV="${APP_ENV:-dev}"
source /opt/greenbrain-platform/infra/scripts/load_env.sh

export GH_REPO_DIR="${GH_REPO_DIR:-/opt/greenbrain-platform/apps/ml-worker}"
PROJECT_DIR="${GH_REPO_DIR}/jobs/parquet_export"
export PYTHONPATH="${GH_REPO_DIR}:${PYTHONPATH:-}"
VENV_PY="${GH_REPO_DIR}/.venv/bin/python"

if [ ! -x "$VENV_PY" ]; then
  echo "ERROR: Python venv not found or not executable: $VENV_PY" >&2
  exit 127
fi
LOG_DIR="/opt/greenbrain-platform/runtime-reports/parquet_export"

# Batch config
BATCH_SIZE=50
MAX_RETRIES_PER_BATCH=4
SLEEP_BETWEEN_RETRIES_SEC=20

# Offsets: 0..800 step 50 (l'ultimo batch prende le famiglie residue)
OFFSETS=(0 50 100 150 200 250 300 350 400 450 500 550 600 650 700 750 800)

mkdir -p "$LOG_DIR"

# Prevent overlapping runs (macOS-safe): atomic mkdir lock
LOCKDIR="/tmp/greenhouse_daily_parquet.lockdir"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  echo "$(date -Iseconds) Another daily parquet run is already running. Exiting."
  exit 0
fi
cleanup_lock() { rmdir "$LOCKDIR" 2>/dev/null || true; }
trap cleanup_lock EXIT INT TERM

ts="$(date +%F_%H-%M-%S)"
master_log="$LOG_DIR/daily_${ts}.log"

echo "$(date -Iseconds) START daily parquet batches" | tee -a "$master_log"
echo "$(date -Iseconds) PROJECT_DIR=$PROJECT_DIR" | tee -a "$master_log"
echo "$(date -Iseconds) BATCH_SIZE=$BATCH_SIZE MAX_RETRIES=$MAX_RETRIES_PER_BATCH" | tee -a "$master_log"
echo "$(date -Iseconds) OFFSETS=${OFFSETS[*]}" | tee -a "$master_log"

cd "$PROJECT_DIR"

# IMPORTANT: daily rolling window (NO FULL_EXPORT)
unset FULL_EXPORT
unset ONLY_YEAR
unset ONLY_FAMILY_SLUG
export BATCH_SIZE="$BATCH_SIZE"

run_one_batch () {
  local off="$1"
  local attempt="$2"
  local batch_log="$LOG_DIR/daily_${ts}_batch_$(printf "%03d" "$off")_try${attempt}.log"

  echo "$(date -Iseconds) [BATCH off=$off attempt=$attempt] START" | tee -a "$master_log"
  export BATCH_OFFSET="$off"

  "$VENV_PY" -u export_features_dense.py 2>&1 | tee -a "$batch_log"
  local exit_code="${PIPESTATUS[0]}"

  if [ "$exit_code" -eq 0 ]; then
    echo "$(date -Iseconds) [BATCH off=$off attempt=$attempt] OK" | tee -a "$master_log"
    return 0
  else
    echo "$(date -Iseconds) [BATCH off=$off attempt=$attempt] FAIL exit_code=$exit_code (see $batch_log)" | tee -a "$master_log"
    return "$exit_code"
  fi
}

overall_failed=0

for off in "${OFFSETS[@]}"; do
  success=0
  for attempt in $(seq 1 "$MAX_RETRIES_PER_BATCH"); do
    if run_one_batch "$off" "$attempt"; then
      success=1
      break
    fi
    echo "$(date -Iseconds) [BATCH off=$off] retry in ${SLEEP_BETWEEN_RETRIES_SEC}s..." | tee -a "$master_log"
    sleep "$SLEEP_BETWEEN_RETRIES_SEC"
  done

  if [ "$success" -ne 1 ]; then
    echo "$(date -Iseconds) [BATCH off=$off] GIVING UP after $MAX_RETRIES_PER_BATCH attempts" | tee -a "$master_log"
    overall_failed=1
  fi
done

if [ "$overall_failed" -eq 0 ]; then
  echo "$(date -Iseconds) SUCCESS all batches completed" | tee -a "$master_log"
  exit 0
else
  echo "$(date -Iseconds) DONE with some FAILED batches (check master log: $master_log)" | tee -a "$master_log"
  exit 2
fi