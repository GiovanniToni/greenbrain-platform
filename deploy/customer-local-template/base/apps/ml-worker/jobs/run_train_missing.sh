#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/opt/greenbrain-platform"
REPO_DIR="${GH_REPO_DIR:-${BASE_DIR}/apps/ml-worker}"
VENV_BIN="${GH_REPO_DIR:-${BASE_DIR}/apps/ml-worker}/.venv/bin"
LOG_DIR="${BASE_DIR}/logs"
LOCK_DIR="${BASE_DIR}/tmp"
LOCK_FILE="${LOCK_DIR}/train_missing.lock"

mkdir -p "$LOG_DIR" "$LOCK_DIR"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") train_missing already running, exiting."
  exit 0
fi

cd "$REPO_DIR"
source "${VENV_BIN}/activate"

# ---- env loader ----
export APP_ENV="${APP_ENV:-dev}"
source /opt/greenbrain-platform/infra/scripts/load_env.sh

stamp=$(date -u +"%Y%m%d_%H%M%S")
logfile="${LOG_DIR}/train_missing_${stamp}.log"

ln -sfn "$logfile" "${LOG_DIR}/train_missing_latest.log"

echo "START $(date -u +"%Y-%m-%dT%H:%M:%SZ")" | tee -a "$logfile"
python -m jobs.train_missing_batches | tee -a "$logfile"
echo "END   $(date -u +"%Y-%m-%dT%H:%M:%SZ")" | tee -a "$logfile"
