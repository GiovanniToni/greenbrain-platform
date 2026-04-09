BEGIN;

INSERT INTO cloud_sync.dashboard_kpis
(
  tenant_code,
  snapshot_ts,
  sales_7d,
  sales_ytd,
  sales_trend_pct,
  sales_ytd_trend_pct,
  products_monitored,
  reorders_week,
  reorder_risk_lines,
  reorder_qty_total,
  source_runtime_ts
)
VALUES
(
  'greenbrain',
  now(),
  12500.00,
  184000.00,
  8.40,
  11.20,
  1420,
  18,
  34,
  290.00,
  now()
),
(
  'cliente1',
  now(),
  7200.00,
  96500.00,
  4.10,
  6.80,
  860,
  9,
  17,
  112.00,
  now()
)
ON CONFLICT DO NOTHING;

INSERT INTO cloud_sync.sales_daily_family
(
  tenant_code,
  sales_date,
  famiglia,
  qty,
  revenue_inc_vat,
  margin_estimate,
  source_runtime_ts
)
VALUES
('greenbrain', current_date - 1, 'rosa', 32, 640.00, 210.00, now()),
('greenbrain', current_date - 1, 'lavanda', 18, 270.00, 95.00, now()),
('cliente1', current_date - 1, 'rosa', 14, 280.00, 90.00, now()),
('cliente1', current_date - 1, 'ficus elastica', 6, 210.00, 78.00, now())
ON CONFLICT DO NOTHING;

INSERT INTO cloud_sync.forecast_summary
(
  tenant_code,
  forecast_date,
  famiglia,
  forecast_qty,
  forecast_revenue_inc_vat,
  model_name,
  model_version,
  confidence_score,
  source_runtime_ts
)
VALUES
('greenbrain', current_date + 7, 'rosa', 45, 900.00, 'tweedie', 'v4', 0.82, now()),
('cliente1', current_date + 7, 'rosa', 22, 440.00, 'tweedie', 'v4', 0.79, now())
ON CONFLICT DO NOTHING;

INSERT INTO cloud_sync.reorder_suggestions
(
  tenant_code,
  suggestion_date,
  codart,
  descrizione,
  famiglia,
  suggested_qty,
  urgency,
  reason,
  source_runtime_ts
)
VALUES
('greenbrain', current_date, 'ART-ROSA-001', 'Rosa vaso 14', 'rosa', 24, 'high', 'copertura stock insufficiente', now()),
('cliente1', current_date, 'ART-FICUS-001', 'Ficus elastica vaso 17', 'ficus elastica', 8, 'medium', 'forecast domanda prossimi 7 giorni', now())
ON CONFLICT DO NOTHING;

COMMIT;
