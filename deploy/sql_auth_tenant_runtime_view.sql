CREATE OR REPLACE VIEW public.v_greenbrain_tenant_runtime_status AS
select
  t.tenant_code,
  t.tenant_name,
  t.access_mode,
  t.status,
  t.login_host,
  t.app_host,
  t.backend_base_url,
  t.runtime_origin,
  t.data_mode,
  rc.connection_mode,
  rc.sync_enabled,
  rc.sync_frequency_minutes,
  rc.last_sync_at,
  rc.last_sync_status,
  rc.local_agent_version,
  rc.runtime_health,
  rc.notes as runtime_notes
from public.greenbrain_tenants t
left join public.greenbrain_runtime_connections rc
  on rc.tenant_code = t.tenant_code;
