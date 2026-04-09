#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/opt/greenbrain-platform"
REPO_DIR="${GH_REPO_DIR:-/opt/greenbrain-platform/apps/ml-worker}"
VENV_BIN="/opt/greenbrain-platform/apps/ml-worker/.venv/bin"
LOG_DIR="/opt/greenbrain-platform/runtime-reports"
LOCK_DIR="/opt/greenbrain-platform/runtime-reports/tmp"
LOCK_FILE="${LOCK_DIR}/predict_all.lock"

mkdir -p "$LOG_DIR" "$LOCK_DIR"

# lock non bloccante: se già in esecuzione, esce
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") predict_all already running, exiting."
  exit 0
fi

cd "$REPO_DIR"
source "${VENV_BIN}/activate"

# ---- env loader ----
export APP_ENV="${APP_ENV:-dev}"
source /opt/greenbrain-platform/infra/scripts/load_env.sh

# ---- load env (DB + Supabase) ----
# ---- run metadata ----
export RUN_TRIGGER_SOURCE="${RUN_TRIGGER_SOURCE:-systemd_timer}"
export GIT_SHA="$(cd "${GH_REPO_DIR}" && git rev-parse --short HEAD 2>/dev/null || true)"

# ---- build + upload priors (Supabase = source of truth) ----
PRIOR_LOG="${LOG_DIR}/build_priors_latest.log"
echo "PRIORS_START $(date -u +"%Y-%m-%dT%H:%M:%SZ")" | tee -a "$PRIOR_LOG"

# 1) slugs list from DB (refresh daily)
psql "$DATABASE_URL" -Atc "
  select distinct lower(trim(famiglia_slug))
  from public.famiglie_catalog_static
  where famiglia_slug is not null
    and trim(famiglia_slug) <> ''
  order by 1;
" > /tmp/slugs_all.txt

echo "[PRIORS] N slugs: $(wc -l < /tmp/slugs_all.txt)" | tee -a "$PRIOR_LOG"

# 2) build priors locally (temp cache)
V4_PRIOR_SMOOTH_DOY="${V4_PRIOR_SMOOTH_DOY:-7}" \
python3 -u -m tools.build_seasonal_priors --slugs-file /tmp/slugs_all.txt | tee -a "$PRIOR_LOG"

# 3) upload/download priors only when Supabase is the active storage backend
if [ "${STORAGE_BACKEND:-supabase}" = "supabase" ]; then
  python3 -u -m jobs.upload_priors_to_supabase | tee -a "$PRIOR_LOG"
  python3 -u -m jobs.download_priors_from_supabase | tee -a "$PRIOR_LOG"
else
  echo "[PRIORS] local backend detected: skip Supabase upload/download" | tee -a "$PRIOR_LOG"
fi

echo "PRIORS_END   $(date -u +"%Y-%m-%dT%H:%M:%SZ")" | tee -a "$PRIOR_LOG"

stamp=$(date -u +"%Y%m%d_%H%M%S")
logfile="${LOG_DIR}/predict_all_${stamp}.log"
ln -sfn "$logfile" "${LOG_DIR}/predict_all_latest.log"

echo "START $(date -u +"%Y-%m-%dT%H:%M:%SZ")" | tee -a "$logfile"
python -m jobs.predict_all | tee -a "$logfile"
echo "END   $(date -u +"%Y-%m-%dT%H:%M:%SZ")" | tee -a "$logfile"

