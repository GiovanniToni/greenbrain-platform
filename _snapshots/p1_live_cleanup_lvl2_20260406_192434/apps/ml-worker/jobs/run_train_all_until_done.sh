#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/opt/greenhouse"
REPO_DIR="${BASE_DIR}/repo"
VENV_BIN="${BASE_DIR}/venv/bin"
LOG_DIR="${BASE_DIR}/logs"
LOCK_DIR="${BASE_DIR}/tmp"
LOCK_FILE="${LOCK_DIR}/train_all.lock"

mkdir -p "$LOG_DIR" "$LOCK_DIR"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") train_all already running, exiting."
  exit 0
fi

cd "$REPO_DIR"
source "${VENV_BIN}/activate"

while true; do
  stamp=$(date -u +"%Y%m%d_%H%M%S")
  logfile="${LOG_DIR}/train_all_${stamp}.log"
  ln -sfn "$logfile" "${LOG_DIR}/train_all_latest.log"

  echo "START $(date -u +"%Y-%m-%dT%H:%M:%SZ")" | tee -a "$logfile"
  python -m jobs.train_all_batches | tee -a "$logfile"
  echo "END   $(date -u +"%Y-%m-%dT%H:%M:%SZ")" | tee -a "$logfile"

  # se ha addestrato 0 in questo giro, abbiamo finito
  if grep -q "DONE train_all | trained=0" "$logfile"; then
    echo "✅ FINITO: non ci sono più famiglie da addestrare (o TRAIN_LIMIT=0 e ha completato tutto)."
    break
  fi

  echo "➡️ Proseguo col prossimo batch..."
done
