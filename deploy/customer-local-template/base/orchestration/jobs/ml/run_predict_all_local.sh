#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/orchestration/lib/common.sh"

gb_load_env

export GH_REPO_DIR="$ROOT/apps/ml-worker"
export GH_LOG_DIR="$GB_LOG_DIR/ml"
export GH_MODELS_DIR="$GB_LOCAL_ROOT/overlay/ml/models_v4"
export LOCAL_STORAGE_ROOT="$GB_LOCAL_ROOT/overlay/ml/storage"
export STORAGE_BACKEND="${STORAGE_BACKEND:-local}"
export PARQUET_ENABLE="${PARQUET_ENABLE:-0}"
export AUTO_TRAIN_MISSING="${AUTO_TRAIN_MISSING:-1}"
export PYTHONPATH="$GH_REPO_DIR:${PYTHONPATH:-}"

mkdir -p "$GH_LOG_DIR" "$GH_MODELS_DIR" "$LOCAL_STORAGE_ROOT"

cd "$GH_REPO_DIR"

gb_log "ML_PREDICT_ALL_START"
python -m jobs.predict_all
gb_log "ML_PREDICT_ALL_DONE"
