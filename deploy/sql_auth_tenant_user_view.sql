CREATE OR REPLACE VIEW public.v_greenbrain_user_tenant_routing AS
select
  u.email,
  u.full_name,
  u.is_admin,
  u.is_active,
  u.tenant_code as user_tenant_code,
  u.home_host as user_home_host,
  u.home_path as user_home_path,
  u.user_role,
  t.tenant_name,
  t.access_mode,
  t.status as tenant_status,
  t.login_host,
  t.app_host,
  t.backend_base_url,
  t.data_mode
from public.greenbrain_users u
left join public.greenbrain_tenants t
  on t.tenant_code = u.tenant_code;
