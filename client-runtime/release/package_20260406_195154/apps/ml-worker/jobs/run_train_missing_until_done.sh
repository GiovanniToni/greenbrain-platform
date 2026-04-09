#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="/opt/greenbrain-platform/apps/ml-worker"
LOG="/opt/greenbrain-platform/runtime-reports/train_missing_latest.log"

cd "$REPO_DIR"

while true; do
  /opt/greenbrain-platform/apps/ml-worker/jobs/run_train_missing.sh || true

  # se nell’ultimo log trovi "batch=0" significa che non ci sono più missing
  if tail -n 200 "$LOG" | grep -q "batch=0"; then
    echo "✅ Nessuna famiglia missing rimasta. Stop."
    exit 0
  fi

  echo "➡️ Proseguo con il prossimo batch..."
  sleep 2
done
