#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Uso:"
  echo "  register_local_runtime_tenant.sh <tenant_code> <tenant_name> <app_host>"
  exit 1
fi

TENANT_CODE="$1"
TENANT_NAME="$2"
APP_HOST="$3"

docker exec -i auth_postgres psql -U greenbrain_auth -d greenbrain_auth <<SQL
INSERT INTO public.greenbrain_tenants
(
  tenant_code,
  tenant_name,
  access_mode,
  status,
  login_host,
  app_host,
  backend_base_url,
  runtime_origin,
  data_mode,
  notes
)
VALUES
(
  '${TENANT_CODE}',
  '${TENANT_NAME}',
  'local-runtime',
  'active',
  'www.greenbrain.it',
  '${APP_HOST}',
  NULL,
  'customer-local',
  'local-db-via-tunnel',
  'Tenant locale con accesso remoto via tunnel sicuro'
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
  notes = EXCLUDED.notes,
  updated_at = now();

INSERT INTO public.greenbrain_runtime_connections
(
  tenant_code,
  connection_mode,
  sync_enabled,
  sync_frequency_minutes,
  last_sync_status,
  local_agent_version,
  runtime_health,
  notes
)
VALUES
(
  '${TENANT_CODE}',
  'reverse-tunnel',
  false,
  NULL,
  'not_connected',
  'not_installed',
  'unknown',
  'Runtime locale con tunnel non ancora installato'
)
ON CONFLICT (tenant_code) DO UPDATE SET
  connection_mode = EXCLUDED.connection_mode,
  sync_enabled = EXCLUDED.sync_enabled,
  sync_frequency_minutes = EXCLUDED.sync_frequency_minutes,
  last_sync_status = EXCLUDED.last_sync_status,
  local_agent_version = EXCLUDED.local_agent_version,
  runtime_health = EXCLUDED.runtime_health,
  notes = EXCLUDED.notes,
  updated_at = now();
SQL

echo "Tenant local-runtime registrato: ${TENANT_CODE}"
