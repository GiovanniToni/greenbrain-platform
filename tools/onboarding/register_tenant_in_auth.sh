#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 8 ]; then
  echo "Uso:"
  echo "  register_tenant_in_auth.sh <tenant_code> <tenant_name> <access_mode> <app_host> <data_mode> <admin_email> <user_role> <connection_mode>"
  exit 1
fi

TENANT_CODE="$1"
TENANT_NAME="$2"
ACCESS_MODE="$3"
APP_HOST="$4"
DATA_MODE="$5"
ADMIN_EMAIL="$6"
USER_ROLE="$7"
CONNECTION_MODE="$8"

docker exec -i auth_postgres psql -U greenbrain_auth -d greenbrain_auth <<SQL
INSERT INTO public.greenbrain_tenants
(
  tenant_code, tenant_name, access_mode, status, login_host, app_host,
  backend_base_url, runtime_origin, data_mode, notes
)
VALUES
(
  '${TENANT_CODE}',
  '${TENANT_NAME}',
  '${ACCESS_MODE}',
  'active',
  'www.greenbrain.it',
  '${APP_HOST}',
  CASE WHEN '${ACCESS_MODE}' = 'hosted' THEN 'https://${APP_HOST}/api' ELSE NULL END,
  CASE WHEN '${ACCESS_MODE}' = 'hosted' THEN 'cloud' ELSE 'customer-local' END,
  '${DATA_MODE}',
  'Registrato via script onboarding'
)
ON CONFLICT (tenant_code) DO UPDATE SET
  tenant_name = EXCLUDED.tenant_name,
  access_mode = EXCLUDED.access_mode,
  status = EXCLUDED.status,
  login_host = EXCLUDED.login_host,
  app_host = EXCLUDED.app_host,
  backend_base_url = EXCLUDED.backend_base_url,
  runtime_origin = EXCLUDED.runtime_origin,
  data_mode = EXCLUDED.data_mode,
  updated_at = now();

INSERT INTO public.greenbrain_runtime_connections
(
  tenant_code, connection_mode, sync_enabled, sync_frequency_minutes,
  last_sync_status, local_agent_version, runtime_health, notes
)
VALUES
(
  '${TENANT_CODE}',
  '${CONNECTION_MODE}',
  CASE WHEN '${CONNECTION_MODE}' = 'cloud-sync' THEN true ELSE false END,
  CASE WHEN '${CONNECTION_MODE}' = 'cloud-sync' THEN 15 ELSE NULL END,
  'never_run',
  'not_installed',
  'unknown',
  'Connessione registrata via script onboarding'
)
ON CONFLICT (tenant_code) DO UPDATE SET
  connection_mode = EXCLUDED.connection_mode,
  sync_enabled = EXCLUDED.sync_enabled,
  sync_frequency_minutes = EXCLUDED.sync_frequency_minutes,
  last_sync_status = EXCLUDED.last_sync_status,
  local_agent_version = EXCLUDED.local_agent_version,
  runtime_health = EXCLUDED.runtime_health,
  updated_at = now();

UPDATE public.greenbrain_users
SET
  tenant_code = '${TENANT_CODE}',
  home_host = '${APP_HOST}',
  home_path = '/dashboard',
  user_role = '${USER_ROLE}'
WHERE email = '${ADMIN_EMAIL}';
SQL

echo "Tenant registrato: ${TENANT_CODE}"
