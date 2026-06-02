#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/orchestration/lib/common.sh"

gb_load_env

LOG="$GB_LOG_DIR/password_sync_$(date +%Y%m%d_%H%M%S).log"
ln -sfn "$(basename "$LOG")" "$GB_LOG_DIR/password_sync_latest.log"

log() {
  gb_log "$*" | tee -a "$LOG"
}

json_field() {
  local file="$1"
  local field="$2"
  python3 - "$file" "$field" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
field = sys.argv[2]

try:
    data = json.loads(path.read_text())
    value = data.get(field, "")
    if value is None:
        value = ""
    print(value)
except Exception:
    print("")
PY
}

mask_json_to_log() {
  local file="$1"
  if [ -f "$file" ]; then
    sed -E 's/("hashed_password"[[:space:]]*:[[:space:]]*")[^"]+/\1***MASKED***/g' "$file" >> "$LOG" 2>/dev/null || true
  fi
}

ack_cloud() {
  local ack_status="$1"
  local ack_error="${2:-}"
  local ack_user_id="${3:-${PENDING_USER_ID:-}}"
  local ack_password_version="${4:-${PENDING_PASSWORD_VERSION:-}}"

  if [ -z "${ACK_URL:-}" ] || [ -z "${PROVISIONING_TOKEN:-}" ] || [ -z "$ack_user_id" ] || [ -z "$ack_password_version" ]; then
    log "PASSWORD_SYNC_ACK_SKIPPED status=$ack_status reason=missing_ack_context"
    return 0
  fi

  local payload_file
  local response_file
  payload_file="$(mktemp)"
  response_file="$(mktemp)"

  ACK_STATUS="$ack_status" \
  ACK_ERROR="$ack_error" \
  ACK_USER_ID="$ack_user_id" \
  ACK_PASSWORD_VERSION="$ack_password_version" \
  python3 - <<'PY' > "$payload_file"
import json
import os

payload = {
    "tenant_code": os.environ.get("TENANT_CODE", ""),
    "installation_id": os.environ.get("INSTALLATION_ID", ""),
    "user_id": os.environ.get("ACK_USER_ID", ""),
    "password_version": int(os.environ.get("ACK_PASSWORD_VERSION", "0")),
    "status": os.environ.get("ACK_STATUS", ""),
    "error": os.environ.get("ACK_ERROR") or None,
}
print(json.dumps(payload))
PY

  local http_code
  http_code="$(curl -sS -o "$response_file" -w '%{http_code}' \
    -X POST "$ACK_URL" \
    -H "Authorization: Bearer $PROVISIONING_TOKEN" \
    -H "Content-Type: application/json" \
    -d @"$payload_file" 2>>"$LOG" || true)"

  log "PASSWORD_SYNC_ACK_HTTP=$http_code status=$ack_status"
  mask_json_to_log "$response_file"

  rm -f "$payload_file" "$response_file"
}

log "PASSWORD_SYNC_START"

if [ "${PASSWORD_SYNC_ENABLED:-true}" != "true" ]; then
  log "PASSWORD_SYNC_DISABLED"
  exit 0
fi

if [ -z "${TENANT_CODE:-}" ]; then
  log "PASSWORD_SYNC_SKIPPED missing TENANT_CODE"
  exit 0
fi

if [ -z "${INSTALLATION_ID:-}" ]; then
  log "PASSWORD_SYNC_SKIPPED missing INSTALLATION_ID"
  exit 0
fi

if [ -z "${PROVISIONING_TOKEN:-}" ]; then
  log "PASSWORD_SYNC_SKIPPED missing PROVISIONING_TOKEN"
  exit 0
fi

if [ -z "${CENTRAL_AUTH_URL:-}" ]; then
  if [ -n "${HEARTBEAT_URL:-}" ]; then
    CENTRAL_AUTH_URL="${HEARTBEAT_URL%/api/v1/customer-runtime/heartbeat}"
  else
    CENTRAL_AUTH_URL="https://www.greenbrain.it"
  fi
fi

PENDING_URL="${PASSWORD_SYNC_PENDING_URL:-${CENTRAL_AUTH_URL%/}/api/v1/customer-runtime/password-sync/pending}"
ACK_URL="${PASSWORD_SYNC_ACK_URL:-${CENTRAL_AUTH_URL%/}/api/v1/customer-runtime/password-sync/ack}"

payload_file="$(mktemp)"
response_file="$(mktemp)"

python3 - <<'PY' > "$payload_file"
import json
import os

print(json.dumps({
    "tenant_code": os.environ.get("TENANT_CODE", ""),
    "installation_id": os.environ.get("INSTALLATION_ID", ""),
}))
PY

http_code="$(curl -sS -o "$response_file" -w '%{http_code}' \
  -X POST "$PENDING_URL" \
  -H "Authorization: Bearer $PROVISIONING_TOKEN" \
  -H "Content-Type: application/json" \
  -d @"$payload_file" 2>>"$LOG" || true)"

rm -f "$payload_file"

log "PASSWORD_SYNC_PENDING_HTTP=$http_code tenant=$TENANT_CODE installation=$INSTALLATION_ID"

if [ "$http_code" != "200" ]; then
  log "PASSWORD_SYNC_PENDING_FAILED http=$http_code"
  mask_json_to_log "$response_file"
  rm -f "$response_file"
  exit 0
fi

has_pending="$(json_field "$response_file" "has_pending")"

if [ "$has_pending" != "True" ] && [ "$has_pending" != "true" ] && [ "$has_pending" != "1" ]; then
  log "PASSWORD_SYNC_NO_PENDING"
  rm -f "$response_file"
  exit 0
fi

PENDING_USER_ID="$(json_field "$response_file" "user_id")"
PENDING_EMAIL="$(json_field "$response_file" "email")"
PENDING_HASHED_PASSWORD="$(json_field "$response_file" "hashed_password")"
PENDING_PASSWORD_VERSION="$(json_field "$response_file" "password_version")"
PENDING_CHANGED_AT="$(json_field "$response_file" "password_changed_at")"

rm -f "$response_file"

if [ -z "$PENDING_USER_ID" ] || [ -z "$PENDING_EMAIL" ] || [ -z "$PENDING_HASHED_PASSWORD" ] || [ -z "$PENDING_PASSWORD_VERSION" ]; then
  log "PASSWORD_SYNC_INVALID_PENDING_PAYLOAD"
  ack_cloud "failed" "invalid_pending_payload" "$PENDING_USER_ID" "${PENDING_PASSWORD_VERSION:-0}"
  exit 0
fi

log "PASSWORD_SYNC_PENDING_FOUND email=$PENDING_EMAIL version=$PENDING_PASSWORD_VERSION hash=***MASKED***"

sql_file="$(mktemp)"
cat > "$sql_file" <<'SQL'
ALTER TABLE public.greenbrain_users
  ADD COLUMN IF NOT EXISTS password_changed_at timestamptz,
  ADD COLUMN IF NOT EXISTS password_changed_by uuid,
  ADD COLUMN IF NOT EXISTS password_change_source text NOT NULL DEFAULT 'initial',
  ADD COLUMN IF NOT EXISTS password_version integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS password_sync_required_at timestamptz,
  ADD COLUMN IF NOT EXISTS password_last_synced_at timestamptz,
  ADD COLUMN IF NOT EXISTS password_last_sync_status text NOT NULL DEFAULT 'not_required',
  ADD COLUMN IF NOT EXISTS password_last_sync_error text,
  ADD COLUMN IF NOT EXISTS password_last_sync_attempt_at timestamptz;

CREATE TABLE IF NOT EXISTS public.greenbrain_user_password_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES public.greenbrain_users(id) ON DELETE SET NULL,
  email text NOT NULL,
  tenant_code text,
  event_type text NOT NULL,
  source text NOT NULL DEFAULT 'local',
  status text NOT NULL DEFAULT 'ok',
  password_version integer,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  details jsonb NOT NULL DEFAULT '{}'::jsonb
);

WITH updated AS (
  UPDATE public.greenbrain_users
  SET
    hashed_password = :'hashed_password',
    password_changed_at = COALESCE(NULLIF(:'password_changed_at', '')::timestamptz, now()),
    password_change_source = 'cloud_sync',
    password_version = :'password_version'::integer,
    password_last_synced_at = now(),
    password_last_sync_attempt_at = now(),
    password_last_sync_status = 'synced',
    password_last_sync_error = NULL
  WHERE lower(email) = lower(:'email')
    AND COALESCE(tenant_code, '') = :'tenant_code'
  RETURNING id, email, tenant_code, password_version
),
event_insert AS (
  INSERT INTO public.greenbrain_user_password_events
    (user_id, email, tenant_code, event_type, source, status, password_version, details)
  SELECT
    id,
    email,
    tenant_code,
    'password_synced_from_cloud',
    'local_runtime',
    'ok',
    password_version,
    jsonb_build_object(
      'cloud_user_id', :'cloud_user_id',
      'installation_id', :'installation_id'
    )
  FROM updated
  RETURNING 1
)
SELECT COUNT(*) AS updated_rows
FROM updated;
SQL

set +e
updated_rows="$(
  gb_psql \
    -v ON_ERROR_STOP=1 \
    -v hashed_password="$PENDING_HASHED_PASSWORD" \
    -v email="$PENDING_EMAIL" \
    -v tenant_code="$TENANT_CODE" \
    -v password_version="$PENDING_PASSWORD_VERSION" \
    -v password_changed_at="$PENDING_CHANGED_AT" \
    -v cloud_user_id="$PENDING_USER_ID" \
    -v installation_id="$INSTALLATION_ID" \
    -At -f "$sql_file" 2>>"$LOG" | tail -n 1
)"
psql_rc=$?
set -e

rm -f "$sql_file"

if [ "$psql_rc" != "0" ]; then
  log "PASSWORD_SYNC_LOCAL_UPDATE_FAILED psql_rc=$psql_rc"
  ack_cloud "failed" "local_update_failed" "$PENDING_USER_ID" "$PENDING_PASSWORD_VERSION"
  exit 0
fi

if [ "${updated_rows:-0}" != "1" ]; then
  log "PASSWORD_SYNC_LOCAL_UPDATE_FAILED updated_rows=${updated_rows:-0}"
  ack_cloud "failed" "local_user_not_found_or_not_updated" "$PENDING_USER_ID" "$PENDING_PASSWORD_VERSION"
  exit 0
fi

log "PASSWORD_SYNC_LOCAL_UPDATED email=$PENDING_EMAIL version=$PENDING_PASSWORD_VERSION"
ack_cloud "synced" "" "$PENDING_USER_ID" "$PENDING_PASSWORD_VERSION"
log "PASSWORD_SYNC_DONE"
