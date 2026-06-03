#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV="$ROOT/overlay/env/customer-local.env"

[ -f "$ENV" ] || { echo "ERROR: missing $ENV"; exit 1; }

set -a
source "$ENV"
set +a

EMAIL="${LOCAL_CUSTOMER_EMAIL:-}"
PASSWORD="${LOCAL_CUSTOMER_TEMP_PASSWORD:-}"
PASSWORD_HASH="${LOCAL_CUSTOMER_PASSWORD_HASH:-}"
PASSWORD_VERSION="${LOCAL_CUSTOMER_PASSWORD_VERSION:-}"
PASSWORD_CHANGED_AT="${LOCAL_CUSTOMER_PASSWORD_CHANGED_AT:-}"
PASSWORD_SYNC_STATUS="${LOCAL_CUSTOMER_PASSWORD_SYNC_STATUS:-}"
PASSWORD_SEED_SOURCE="${LOCAL_CUSTOMER_PASSWORD_SEED_SOURCE:-}"
FULL_NAME="${LOCAL_CUSTOMER_FULL_NAME:-}"
TENANT="${LOCAL_CUSTOMER_TENANT_CODE:-${TENANT_CODE:-}}"
HOME_HOST="${LOCAL_CUSTOMER_HOME_HOST:-${TENANT}.greenbrain.it}"
HOME_PATH="${LOCAL_CUSTOMER_HOME_PATH:-/dashboard}"
USER_ROLE="${LOCAL_CUSTOMER_USER_ROLE:-customer_admin}"

if [ -z "$EMAIL" ] || [ -z "$TENANT" ] || { [ -z "$PASSWORD" ] && [ -z "$PASSWORD_HASH" ]; }; then
  echo "LOCAL_USER_PROVISION_SKIPPED missing LOCAL_CUSTOMER_EMAIL/(LOCAL_CUSTOMER_TEMP_PASSWORD or LOCAL_CUSTOMER_PASSWORD_HASH)/TENANT"
  exit 0
fi

COMPOSE_FILE="$ROOT/docker-compose.local.yml"
if [ -f "$ROOT/docker-compose.prebuilt.yml" ]; then
  COMPOSE_FILE="$ROOT/docker-compose.prebuilt.yml"
fi

echo "== GreenBrain Local User Provisioning =="
echo "email: $EMAIL"
echo "tenant: $TENANT"
echo "home: https://$HOME_HOST$HOME_PATH"

docker compose --env-file "$ENV" -f "$COMPOSE_FILE" exec -T \
  -e AUTH_DB_HOST=postgres \
  -e AUTH_DB_PORT=5432 \
  -e AUTH_DB_NAME="${POSTGRES_DB}" \
  -e AUTH_DB_USER="${POSTGRES_USER}" \
  -e AUTH_DB_PASSWORD="${POSTGRES_PASSWORD}" \
  -e LOCAL_CUSTOMER_PASSWORD_VERSION="${PASSWORD_VERSION}" \
  -e LOCAL_CUSTOMER_PASSWORD_CHANGED_AT="${PASSWORD_CHANGED_AT}" \
  -e LOCAL_CUSTOMER_PASSWORD_SYNC_STATUS="${PASSWORD_SYNC_STATUS}" \
  -e LOCAL_CUSTOMER_PASSWORD_SEED_SOURCE="${PASSWORD_SEED_SOURCE}" \
  backend python - <<'PY'
import os
from app.services.customer_auth_user_service import provision_customer_auth_user

email = os.environ.get("LOCAL_CUSTOMER_EMAIL", "").strip().lower()
password = os.environ.get("LOCAL_CUSTOMER_TEMP_PASSWORD", "").strip()
password_hash = os.environ.get("LOCAL_CUSTOMER_PASSWORD_HASH", "").strip()
password_version_raw = os.environ.get("LOCAL_CUSTOMER_PASSWORD_VERSION", "").strip()
password_changed_at = os.environ.get("LOCAL_CUSTOMER_PASSWORD_CHANGED_AT", "").strip() or None
password_sync_status = os.environ.get("LOCAL_CUSTOMER_PASSWORD_SYNC_STATUS", "").strip() or None
password_seed_source = os.environ.get("LOCAL_CUSTOMER_PASSWORD_SEED_SOURCE", "").strip() or None
password_version = int(password_version_raw) if password_version_raw.isdigit() else None
full_name = os.environ.get("LOCAL_CUSTOMER_FULL_NAME", "").strip() or None
tenant = (os.environ.get("LOCAL_CUSTOMER_TENANT_CODE") or os.environ.get("TENANT_CODE") or "").strip()
home_host = (os.environ.get("LOCAL_CUSTOMER_HOME_HOST") or (tenant + ".greenbrain.it")).strip()
home_path = (os.environ.get("LOCAL_CUSTOMER_HOME_PATH") or "/dashboard").strip()
user_role = (os.environ.get("LOCAL_CUSTOMER_USER_ROLE") or "customer_admin").strip()

if not email or not tenant or (not password and not password_hash):
    raise SystemExit("LOCAL_USER_PROVISION_FAILED missing env")

row = provision_customer_auth_user(
    email=email,
    password=password or None,
    password_hash=password_hash or None,
    full_name=full_name,
    tenant_code=tenant,
    home_host=home_host,
    home_path=home_path,
    user_role=user_role,
    password_version=password_version,
    password_changed_at=password_changed_at,
    password_seed_source=password_seed_source,
    password_sync_status=password_sync_status,
)

print("LOCAL_USER_PROVISION_OK")
print(row)
PY
