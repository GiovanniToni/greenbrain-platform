#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV="$ROOT/overlay/env/customer-local.env"

[ -f "$ENV" ] || { echo "ERROR: missing $ENV"; exit 1; }

set -a
source "$ENV"
set +a

echo "== GreenBrain Local Extended Doctor =="

docker compose -f "$ROOT/docker-compose.local.yml" --env-file "$ENV" ps

echo
echo "== HTTP health =="
bash "$ROOT/base/scripts/doctor-local.sh"

echo
echo "== DB checks =="
docker compose -f "$ROOT/docker-compose.local.yml" --env-file "$ENV" exec -T postgres \
  psql -U "${POSTGRES_USER:-greenbrain}" -d "${POSTGRES_DB:-greenbrain}" -P pager=off -c "
select 'features_unique_index' as check_name, to_regclass('public.ux_greenhouse_forecast_features_dense_key')::text as result
union all
select 'routing_view', to_regclass('ml_forecast.v_family_execution_routing_v2')::text
union all
select 'mv_famiglie_catalog', to_regclass('public.mv_famiglie_catalog')::text;
"

echo
echo "== ML worker import smoke =="
docker compose -f "$ROOT/docker-compose.local.yml" --env-file "$ENV" run --rm ml-worker \
  bash -lc 'cd /workspace/base/apps/ml-worker && python - <<PY
import jobs.predict_all
import jobs.train_missing_batches
print("ml imports: OK")
PY'

echo

echo
echo "== Scheduler cron =="
docker compose -f "$ROOT/docker-compose.local.yml" --env-file "$ENV" exec -T scheduler \
  sh -lc 'crontab -l | grep -E "runtime-heartbeat|run_daily_sequence"'

echo
echo "== ML latest logs =="
ls -lah "$ROOT/overlay/logs/ml" 2>/dev/null || true

echo "== Latest daily sequence log =="
if [ -L "$ROOT/overlay/logs/daily_sequence_latest.log" ]; then
  tail -80 "$ROOT/overlay/logs/$(basename "$(readlink "$ROOT/overlay/logs/daily_sequence_latest.log")")"
else
  echo "No daily_sequence_latest.log yet"
fi

echo
echo "EXTENDED_DOCTOR_OK"
