CREATE OR REPLACE VIEW public.v_cloud_sync_status AS
select
  t.tenant_code,
  t.tenant_name,
  t.access_mode,
  t.data_mode,
  rc.connection_mode,
  rc.sync_enabled,
  rc.sync_frequency_minutes,
  rc.last_sync_at,
  rc.last_sync_status,
  rc.runtime_health,
  (
    select max(k.snapshot_ts)
    from cloud_sync.dashboard_kpis k
    where k.tenant_code = t.tenant_code
  ) as last_dashboard_kpi_sync_at,
  (
    select max(s.sales_date)::timestamptz
    from cloud_sync.sales_daily_family s
    where s.tenant_code = t.tenant_code
  ) as last_sales_family_sync_at,
  (
    select max(f.forecast_date)::timestamptz
    from cloud_sync.forecast_summary f
    where f.tenant_code = t.tenant_code
  ) as last_forecast_sync_at,
  (
    select max(r.suggestion_date)::timestamptz
    from cloud_sync.reorder_suggestions r
    where r.tenant_code = t.tenant_code
  ) as last_reorder_sync_at
from public.greenbrain_tenants t
left join public.greenbrain_runtime_connections rc
  on rc.tenant_code = t.tenant_code;
