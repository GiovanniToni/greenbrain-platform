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
FULL_NAME="${LOCAL_CUSTOMER_FULL_NAME:-}"
TENANT="${LOCAL_CUSTOMER_TENANT_CODE:-${TENANT_CODE:-}}"
HOME_HOST="${LOCAL_CUSTOMER_HOME_HOST:-${TENANT}.greenbrain.it}"
HOME_PATH="${LOCAL_CUSTOMER_HOME_PATH:-/dashboard}"
USER_ROLE="${LOCAL_CUSTOMER_USER_ROLE:-customer_admin}"

if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ] || [ -z "$TENANT" ]; then
  echo "LOCAL_USER_PROVISION_SKIPPED missing LOCAL_CUSTOMER_EMAIL/LOCAL_CUSTOMER_TEMP_PASSWORD/TENANT"
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

docker compose --env-file "$ENV" -f "$COMPOSE_FILE" exec -T backend python - <<'PY'
import os
from app.services.customer_auth_user_service import provision_customer_auth_user

email = os.environ.get("LOCAL_CUSTOMER_EMAIL", "").strip().lower()
password = os.environ.get("LOCAL_CUSTOMER_TEMP_PASSWORD", "").strip()
full_name = os.environ.get("LOCAL_CUSTOMER_FULL_NAME", "").strip() or None
tenant = (os.environ.get("LOCAL_CUSTOMER_TENANT_CODE") or os.environ.get("TENANT_CODE") or "").strip()
home_host = (os.environ.get("LOCAL_CUSTOMER_HOME_HOST") or (tenant + ".greenbrain.it")).strip()
home_path = (os.environ.get("LOCAL_CUSTOMER_HOME_PATH") or "/dashboard").strip()
user_role = (os.environ.get("LOCAL_CUSTOMER_USER_ROLE") or "customer_admin").strip()

if not email or not password or not tenant:
    raise SystemExit("LOCAL_USER_PROVISION_FAILED missing env")

row = provision_customer_auth_user(
    email=email,
    password=password,
    full_name=full_name,
    tenant_code=tenant,
    home_host=home_host,
    home_path=home_path,
    user_role=user_role,
)

print("LOCAL_USER_PROVISION_OK")
print(row)
PY
