#!/usr/bin/env bash
set -euo pipefail

GB_BASE="${GB_BASE:-/opt/greenbrain-platform}"
cd "$GB_BASE"

source "$GB_BASE/infra/scripts/load_env.sh"

export RUN_TRIGGER_SOURCE="${RUN_TRIGGER_SOURCE:-daily_sequence}"
export GB_TRIGGER_MODE="${GB_TRIGGER_MODE:-${RUN_TRIGGER_SOURCE}}"
export TRIGGER_MODE="${TRIGGER_MODE:-${GB_TRIGGER_MODE}}"

RAW_STABLE_MINUTES="${RAW_STABLE_MINUTES:-20}"
RAW_WAIT_TIMEOUT_MINUTES="${RAW_WAIT_TIMEOUT_MINUTES:-180}"
RAW_POLL_SECONDS="${RAW_POLL_SECONDS:-300}"

deadline=$(( $(date +%s) + RAW_WAIT_TIMEOUT_MINUTES * 60 ))

echo "===== GREENBRAIN DAILY SEQUENCE ====="
echo "RAW_STABLE_MINUTES=$RAW_STABLE_MINUTES"
echo "RAW_WAIT_TIMEOUT_MINUTES=$RAW_WAIT_TIMEOUT_MINUTES"
echo

while true; do
  row="$(psql "$DATABASE_URL" -At -P pager=off -c "
    select
      coalesce(max(data_movimento)::text,'') || '|' ||
      coalesce(max(load_timestamp)::text,'') || '|' ||
      case
        when max(load_timestamp) is null then 'false'
        when ((now() at time zone 'UTC') - max(load_timestamp)) >= interval '${RAW_STABLE_MINUTES} minutes' then 'true'
        else 'false'
      end
    from public.greenhouse_sales_raw;
  ")"

  raw_max_data="$(echo "$row" | cut -d'|' -f1)"
  raw_last_load_ts="$(echo "$row" | cut -d'|' -f2)"
  raw_ready="$(echo "$row" | cut -d'|' -f3)"

  echo "$(date --iso-8601=seconds) RAW max_data=$raw_max_data last_load_ts=$raw_last_load_ts ready=$raw_ready"

  if [ "$raw_ready" = "true" ]; then
    break
  fi

  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "ERROR: RAW not stable before timeout"
    exit 20
  fi

  sleep "$RAW_POLL_SECONDS"
done

echo
echo "===== STEP 1: DAILY PIPELINE ====="
"$GB_BASE/orchestration/jobs/pipeline/run_daily_pipeline.sh"

echo
echo "===== STEP 2: PARQUET EXPORT ====="
bash "$GB_BASE/orchestration/jobs/parquet/check_etl_ready.sh"
bash "$GB_BASE/orchestration/jobs/parquet/run_daily_parquet_batches.sh"

echo
echo "===== STEP 3: REFRESH REGISTRY ====="
"$GB_BASE/orchestration/jobs/registry/gh-refresh-registry"

echo
echo "===== STEP 4: TRAIN MISSING ====="
bash "$GB_BASE/orchestration/jobs/ml/run_train_missing.sh"

echo
echo "===== STEP 5: PREDICT ALL ====="
bash "$GB_BASE/orchestration/jobs/ml/run_predict_all.sh"

echo
echo "===== FINAL SNAPSHOT ====="
"$GB_BASE/orchestration/scripts/gh-runtime-snapshot"

echo
echo "DAILY_SEQUENCE_DONE"
