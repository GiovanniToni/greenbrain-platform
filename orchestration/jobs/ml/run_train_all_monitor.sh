#!/usr/bin/env bash
set -euo pipefail

GB_BASE="${GB_BASE:-/opt/greenbrain-platform}"
APP_DIR="$GB_BASE/apps/ml-worker"

cd "$APP_DIR"

source "$GB_BASE/infra/scripts/load_env.sh"
source "$APP_DIR/.venv/bin/activate"

export RUN_TRIGGER_SOURCE="${RUN_TRIGGER_SOURCE:-systemd_timer}"
export GIT_SHA="${GIT_SHA:-$(cd "${GH_REPO_DIR:-$APP_DIR}" && git rev-parse --short HEAD 2>/dev/null || true)}"

python3 -u jobs/train_all_monitor.py
