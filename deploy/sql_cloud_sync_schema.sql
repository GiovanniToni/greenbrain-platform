BEGIN;

CREATE SCHEMA IF NOT EXISTS cloud_sync;

CREATE TABLE IF NOT EXISTS cloud_sync.dashboard_kpis (
  tenant_code text NOT NULL REFERENCES public.greenbrain_tenants(tenant_code) ON DELETE CASCADE,
  snapshot_ts timestamptz NOT NULL DEFAULT now(),
  sales_7d numeric(14,2),
  sales_ytd numeric(14,2),
  sales_trend_pct numeric(8,2),
  sales_ytd_trend_pct numeric(8,2),
  products_monitored integer,
  reorders_week integer,
  reorder_risk_lines integer,
  reorder_qty_total numeric(14,2),
  source_runtime_ts timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_code, snapshot_ts)
);

CREATE INDEX IF NOT EXISTS idx_dashboard_kpis_tenant_snapshot
  ON cloud_sync.dashboard_kpis (tenant_code, snapshot_ts DESC);

CREATE TABLE IF NOT EXISTS cloud_sync.sales_daily_family (
  tenant_code text NOT NULL REFERENCES public.greenbrain_tenants(tenant_code) ON DELETE CASCADE,
  sales_date date NOT NULL,
  famiglia text NOT NULL,
  qty numeric(14,3),
  revenue_inc_vat numeric(14,2),
  margin_estimate numeric(14,2),
  source_runtime_ts timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_code, sales_date, famiglia)
);

CREATE INDEX IF NOT EXISTS idx_sales_daily_family_tenant_date
  ON cloud_sync.sales_daily_family (tenant_code, sales_date DESC);

CREATE INDEX IF NOT EXISTS idx_sales_daily_family_tenant_family
  ON cloud_sync.sales_daily_family (tenant_code, famiglia);

CREATE TABLE IF NOT EXISTS cloud_sync.forecast_summary (
  tenant_code text NOT NULL REFERENCES public.greenbrain_tenants(tenant_code) ON DELETE CASCADE,
  forecast_date date NOT NULL,
  famiglia text NOT NULL,
  forecast_qty numeric(14,3),
  forecast_revenue_inc_vat numeric(14,2),
  model_name text,
  model_version text,
  confidence_score numeric(8,4),
  source_runtime_ts timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_code, forecast_date, famiglia)
);

CREATE INDEX IF NOT EXISTS idx_forecast_summary_tenant_date
  ON cloud_sync.forecast_summary (tenant_code, forecast_date DESC);

CREATE TABLE IF NOT EXISTS cloud_sync.reorder_suggestions (
  tenant_code text NOT NULL REFERENCES public.greenbrain_tenants(tenant_code) ON DELETE CASCADE,
  suggestion_date date NOT NULL,
  codart text NOT NULL,
  descrizione text,
  famiglia text,
  suggested_qty numeric(14,3),
  urgency text,
  reason text,
  source_runtime_ts timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_code, suggestion_date, codart)
);

CREATE INDEX IF NOT EXISTS idx_reorder_suggestions_tenant_date
  ON cloud_sync.reorder_suggestions (tenant_code, suggestion_date DESC);

COMMIT;
