-- GreenBrain Client Runtime — Wave 7B.2-H Dashboard KPIs
--
-- STATUS: PLANNED
--
-- Scope: exactly 1 endpoint:
--   /api/v1/dashboard/kpis
--
-- Backend RPC:
--   dashboard__kpis_v2()
--
-- Strategy:
--   SAFE LOCAL STUB (no dependencies)
--
-- Objects:
--   1 function
--
-- No tables
-- No views
-- No matviews
-- No extensions
--

SET search_path = public;

CREATE OR REPLACE FUNCTION public.dashboard__kpis_v2()
RETURNS TABLE(
    sales_week numeric,
    sales_trend numeric,
    stock_out_risk bigint,
    products_monitored bigint,
    forecast_14d numeric,
    reorder_lines bigint,
    reorder_risk_lines bigint,
    reorder_qty_tot numeric,
    sales_ytd numeric,
    sales_ytd_trend numeric
)
LANGUAGE sql STABLE
AS $$
SELECT
    0::numeric  AS sales_week,
    NULL::numeric AS sales_trend,

    0::bigint   AS stock_out_risk,
    0::bigint   AS products_monitored,

    0::numeric  AS forecast_14d,

    0::bigint   AS reorder_lines,
    0::bigint   AS reorder_risk_lines,
    0::numeric  AS reorder_qty_tot,

    0::numeric  AS sales_ytd,
    NULL::numeric AS sales_ytd_trend;
$$;

