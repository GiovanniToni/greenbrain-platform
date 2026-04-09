#!/usr/bin/env bash
set -euo pipefail

FAM="${1:?missing family}"

BASE="/opt/greenhouse"
REPO="$BASE/repo"
VENV="$BASE/venv/bin/activate"
LOGDIR="$BASE/logs/train_all_parallel"
mkdir -p "$LOGDIR"

cd "$REPO"
source "$VENV"
set +H
set -a
export APP_ENV="${APP_ENV:-dev}"
source /opt/greenbrain-platform/infra/scripts/load_env.sh
set +a

RUN_TRIGGER_SOURCE="${RUN_TRIGGER_SOURCE:-manual}"
RUN_TYPE="${RUN_TYPE:-train_family_manual}"
MODEL_VERSION="${MODEL_VERSION:-v4}"
PARENT_RUN_ID="${PARENT_RUN_ID:-}"

OPS_PIPELINE_RUN_ID=""
OPS_FAMILY_RUN_ID=""
FAMILY_NAME_CANON=""
FAMILY_SLUG_CANON=""
MODEL_CODE_CANON=""
DEMAND_CLASS_CANON=""
LOG_TS="$(date -u +%Y%m%d_%H%M%S)"

resolve_family() {
  python3 - "$FAM" <<'PY'
import sys
import sqlalchemy as sa

sys.path.insert(0, "/opt/greenhouse/repo")
from jobs.predict_all import get_engine
from jobs.family_resolver import resolve_family_and_slug

fam = sys.argv[1]
engine = get_engine()
try:
    fam_name, fam_slug = resolve_family_and_slug(engine, fam)
    with engine.connect() as conn:
        row = conn.execute(sa.text("""
            select demand_class_final, model_code
            from ml_forecast.family_model_registry_v2
            where family_name = :family_name
            limit 1
        """), {"family_name": fam_name}).fetchone()
finally:
    engine.dispose()

demand_class = row[0] if row else None
model_code = row[1] if row else None

print(f"{fam_name}|{fam_slug}|{demand_class or ''}|{model_code or ''}")
PY
}

start_monitor() {
  python3 - "$FAMILY_NAME_CANON" "$FAMILY_SLUG_CANON" "$RUN_TRIGGER_SOURCE" "$MODEL_VERSION" "$DEMAND_CLASS_CANON" "$MODEL_CODE_CANON" <<'PY'
import os
import sys

sys.path.insert(0, "/opt/greenhouse/repo")
from jobs.ml_ops_bridge import start_pipeline_run, start_family_run

fam_name = sys.argv[1]
fam_slug = sys.argv[2]
trigger = sys.argv[3]
model_version = sys.argv[4]
demand_class = sys.argv[5].strip() or None
model_code = sys.argv[6].strip() or None

ops_pipeline_run_id = start_pipeline_run(
    job_type="train_family",
    trigger_mode=trigger,
    notes=f"family={fam_name}; slug={fam_slug}; model_version={model_version}",
    git_sha=os.getenv("GIT_SHA"),
)

ops_family_run_id = start_family_run(
    ops_pipeline_run_id,
    "train",
    fam_name,
    demand_class,
    model_code,
)

print(f"{ops_pipeline_run_id}|{ops_family_run_id}")
PY
}

finish_ok() {
  python3 - "$FAMILY_NAME_CANON" "$FAMILY_SLUG_CANON" "$MODEL_CODE_CANON" "$OPS_PIPELINE_RUN_ID" "$OPS_FAMILY_RUN_ID" <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, "/opt/greenhouse/repo")
from jobs.ml_ops_bridge import finish_pipeline_run, finish_family_run, mark_train_success

fam_name = sys.argv[1]
fam_slug = sys.argv[2]
model_code = sys.argv[3] or None
ops_pipeline_run_id = int(sys.argv[4]) if sys.argv[4] else None
ops_family_run_id = int(sys.argv[5]) if sys.argv[5] else None

bundle_path = f"/opt/greenhouse/repo/models_v4/bundle_{fam_slug}_v4.pkl"
bp = Path(bundle_path)

if ops_family_run_id is not None:
    try:
        finish_family_run(
            ops_family_run_id,
            status="success",
            artifact_path=bundle_path if bp.exists() else None,
        )
    except Exception as e:
        print(f"MLOPS finish_family_run WARN: {e}")

if ops_pipeline_run_id is not None:
    try:
        finish_pipeline_run(
            ops_pipeline_run_id,
            status="success",
            rows_processed=1,
            notes=f"family={fam_name} train ok",
        )
    except Exception as e:
        print(f"MLOPS finish_pipeline_run WARN: {e}")

if ops_pipeline_run_id is not None:
    try:
        mark_train_success(
            family_name=fam_name,
            pipeline_run_id=ops_pipeline_run_id,
            model_code=model_code,
            train_max_date=None,
            notes="train_one_safe ok",
        )
    except Exception as e:
        print(f"MLOPS mark_train_success WARN: {e}")
PY
}

finish_fail() {
  local rc="${1:-1}"

  python3 - "$FAMILY_NAME_CANON" "$OPS_PIPELINE_RUN_ID" "$OPS_FAMILY_RUN_ID" "$rc" <<'PY'
import sys

sys.path.insert(0, "/opt/greenhouse/repo")
from jobs.ml_ops_bridge import finish_pipeline_run, finish_family_run, mark_train_failed

fam_name = sys.argv[1]
ops_pipeline_run_id = int(sys.argv[2]) if sys.argv[2] else None
ops_family_run_id = int(sys.argv[3]) if sys.argv[3] else None
rc = int(sys.argv[4])

if ops_family_run_id is not None:
    try:
        finish_family_run(
            ops_family_run_id,
            status="failed",
            error_message=f"train failed rc={rc}",
        )
    except Exception as e:
        print(f"MLOPS finish_family_run WARN: {e}")

if ops_pipeline_run_id is not None:
    try:
        finish_pipeline_run(
            ops_pipeline_run_id,
            status="failed",
            rows_processed=0,
            error_message=f"train failed rc={rc}",
            notes=f"family={fam_name} train failed",
        )
    except Exception as e:
        print(f"MLOPS finish_pipeline_run WARN: {e}")

if ops_pipeline_run_id is not None:
    try:
        mark_train_failed(
            family_name=fam_name,
            pipeline_run_id=ops_pipeline_run_id,
            error_message=f"train failed rc={rc}",
        )
    except Exception as e:
        print(f"MLOPS mark_train_failed WARN: {e}")
PY
}

IFS='|' read -r FAMILY_NAME_CANON FAMILY_SLUG_CANON DEMAND_CLASS_CANON MODEL_CODE_CANON <<< "$(resolve_family)"

SAFE="$(echo "$FAMILY_SLUG_CANON" | tr '/' '_' | tr -cd '[:alnum:]_àèéìòùÀÈÉÌÒÙ-')"
LOG_RUN="$LOGDIR/${SAFE}_${LOG_TS}.log"
LOG_LATEST="$LOGDIR/${SAFE}.log"

ln -sfn "$LOG_RUN" "$LOG_LATEST"

IFS='|' read -r OPS_PIPELINE_RUN_ID OPS_FAMILY_RUN_ID <<< "$(start_monitor)"

for attempt in 1 2 3; do
  echo "=== $(date -u +%FT%TZ) | FAMILY=$FAMILY_NAME_CANON | SLUG=$FAMILY_SLUG_CANON | attempt=$attempt ===" | tee -a "$LOG_RUN"

  if timeout -k 30 2700 python -m jobs.train_family_router --family "$FAMILY_NAME_CANON" >>"$LOG_RUN" 2>&1; then
    python -c "from jobs.ensure_model_bundle import upload_bundle; ok,msg=upload_bundle('$FAMILY_SLUG_CANON'); print(msg)" >>"$LOG_RUN" 2>&1 || true
    echo "=== OK $(date -u +%FT%TZ) | FAMILY=$FAMILY_NAME_CANON | SLUG=$FAMILY_SLUG_CANON ===" | tee -a "$LOG_RUN"
    finish_ok
    exit 0
  else
    RC=$?
    echo "=== FAIL $(date -u +%FT%TZ) | FAMILY=$FAMILY_NAME_CANON | SLUG=$FAMILY_SLUG_CANON | attempt=$attempt | rc=$RC ===" | tee -a "$LOG_RUN"
    sleep $((attempt*5))
  fi
done

echo "=== GIVEUP $(date -u +%FT%TZ) | FAMILY=$FAMILY_NAME_CANON | SLUG=$FAMILY_SLUG_CANON ===" | tee -a "$LOG_RUN"
finish_fail 1
exit 1
