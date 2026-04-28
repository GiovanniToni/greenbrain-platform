-- GreenBrain Client Runtime — Wave 7B.1 Minimal Schema Contract
--
-- STATUS: PLANNED — not yet applied to client-runtime postgres
--
-- This file is hand-crafted. It is NOT extracted from the Supabase/dev schema snapshot.
-- Column definitions were verified against sql/schema/current-schema.sql.
--
-- Design principles:
--   1. Only the objects actually queried by backend API endpoints (Tier 2)
--   2. Views reference t_core_analytics__* tables DIRECTLY, bypassing the
--      intermediate view chain (core_analytics__* → mv_* matview → t_* table)
--      that exists in dev/Supabase but is not needed for query correctness
--   3. IF NOT EXISTS on all objects — idempotent, safe to re-run
--   4. No extensions, no RPCs, no cross-schema references, no Supabase-specific syntax
--   5. Empty tables on first boot — endpoints return HTTP 200 with {"count":0,"items":[]}
--
-- Apply order (if running manually):
--   psql -U greenbrain -d greenbrain -f wave_7b1_planned.sql
--
-- To apply as init script:
--   cp wave_7b1_planned.sql /path/to/client-runtime/sql/init/02_schema_7b1.sql
--   docker-compose -f docker-compose.yml down && docker volume rm docker_postgres_data
--   docker-compose -f docker-compose.yml up -d
--
-- Endpoints unlocked after applying this file:
--   /api/v1/catalog/families          → 200 empty
--   /api/v1/forecast/summary          → 200 empty
--   /api/v1/forecast/series           → 200 empty
--   /api/v1/forecast/sample           → 200 empty
--   /api/v1/analytics/future-windows  → 200 empty
--   /api/v1/analytics/series          → 200 empty (all granularities, all entity types)
--   /api/v1/analytics/series-bounds   → 200 empty
--   /api/v1/analytics/seasonality     → 200 empty
--   /api/v1/sales/summary             → 200 empty
--   /api/v1/dashboard/sales-weekly    → 200 empty
--   /api/v1/dashboard/sales-monthly   → 200 empty
--   /api/v1/dashboard/sales-yearly    → 200 empty
--
-- Still returns 500 after this file (deferred to Wave 7B.2):
--   /api/v1/analytics/series-breakdown, /api/v1/analytics/entity-summary,
--   /api/v1/analytics/range-totals, /api/v1/analytics/compare-series,
--   /api/v1/analytics/components, /api/v1/analytics/stock-and-reorder,
--   /api/v1/catalog/search, /api/v1/catalog/children, /api/v1/catalog/list,
--   /api/v1/dashboard/kpis, /api/v1/dashboard/reorder-suggestions,
--   /api/v1/planner/*, /api/v1/ops/pipeline-status, /api/v1/ops/family-runs
--

SET search_path = public;


-- ============================================================
-- SECTION 1: CATALOG
-- ============================================================

CREATE TABLE IF NOT EXISTS public.famiglie_catalog_static (
    famiglia       text NOT NULL,
    famiglia_slug  text
);


-- ============================================================
-- SECTION 2: FORECAST
-- ============================================================

CREATE TABLE IF NOT EXISTS public.greenhouse_forecast_results_v2 (
    data                  date NOT NULL,
    famiglia              text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_forecast          numeric(12,3) NOT NULL,
    created_at            timestamp without time zone DEFAULT now()
);


-- ============================================================
-- SECTION 3: ANALYTICS SERIES — DAILY (4 entity types)
-- Same 8-column schema for all four.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.t_core_analytics__series_daily_famiglia (
    data                 date    NOT NULL,
    entity_key           text    NOT NULL,
    qty_venduta_tot      numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot     numeric,
    is_holiday           boolean,
    holiday_name         text,
    dow                  integer
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__series_daily_categoria (
    data                 date    NOT NULL,
    entity_key           text    NOT NULL,
    qty_venduta_tot      numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot     numeric,
    is_holiday           boolean,
    holiday_name         text,
    dow                  integer
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__series_daily_fascia (
    data                 date    NOT NULL,
    entity_key           text    NOT NULL,
    qty_venduta_tot      numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot     numeric,
    is_holiday           boolean,
    holiday_name         text,
    dow                  integer
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__series_daily_fascia_prezzo (
    data                 date    NOT NULL,
    entity_key           text    NOT NULL,
    qty_venduta_tot      numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot     numeric,
    is_holiday           boolean,
    holiday_name         text,
    dow                  integer
);


-- ============================================================
-- SECTION 4: ANALYTICS SERIES — WEEKLY (4 entity types)
-- 5-column schema: no holiday/dow (period aggregates).
-- ============================================================

CREATE TABLE IF NOT EXISTS public.t_core_analytics__series_weekly_famiglia (
    period_start         date NOT NULL,
    entity_key           text NOT NULL,
    qty_venduta_tot      numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot     numeric
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__series_weekly_categoria (
    period_start         date NOT NULL,
    entity_key           text NOT NULL,
    qty_venduta_tot      numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot     numeric
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__series_weekly_fascia (
    period_start         date NOT NULL,
    entity_key           text NOT NULL,
    qty_venduta_tot      numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot     numeric
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__series_weekly_fascia_prezzo (
    period_start         date NOT NULL,
    entity_key           text NOT NULL,
    qty_venduta_tot      numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot     numeric
);


-- ============================================================
-- SECTION 5: ANALYTICS SERIES — MONTHLY (same as weekly)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.t_core_analytics__series_monthly_famiglia (
    period_start         date NOT NULL,
    entity_key           text NOT NULL,
    qty_venduta_tot      numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot     numeric
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__series_monthly_categoria (
    period_start         date NOT NULL,
    entity_key           text NOT NULL,
    qty_venduta_tot      numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot     numeric
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__series_monthly_fascia (
    period_start         date NOT NULL,
    entity_key           text NOT NULL,
    qty_venduta_tot      numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot     numeric
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__series_monthly_fascia_prezzo (
    period_start         date NOT NULL,
    entity_key           text NOT NULL,
    qty_venduta_tot      numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot     numeric
);


-- ============================================================
-- SECTION 6: ANALYTICS SERIES — YEARLY (different schema)
-- entity_key_lc already lowercased in table; stricter numeric types.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.t_core_analytics__series_yearly_famiglia (
    period_start         date              NOT NULL,
    entity_key_lc        text              NOT NULL,
    qty_venduta_tot      numeric(12,3)     NOT NULL DEFAULT 0,
    imponibile_netto_tot numeric(12,2)     NOT NULL DEFAULT 0,
    qty_forecast_tot     numeric(12,3)
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__series_yearly_categoria (
    period_start         date              NOT NULL,
    entity_key_lc        text              NOT NULL,
    qty_venduta_tot      numeric(12,3)     NOT NULL DEFAULT 0,
    imponibile_netto_tot numeric(12,2)     NOT NULL DEFAULT 0,
    qty_forecast_tot     numeric(12,3)
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__series_yearly_fascia (
    period_start         date              NOT NULL,
    entity_key_lc        text              NOT NULL,
    qty_venduta_tot      numeric(12,3)     NOT NULL DEFAULT 0,
    imponibile_netto_tot numeric(12,2)     NOT NULL DEFAULT 0,
    qty_forecast_tot     numeric(12,3)
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__series_yearly_fascia_prezzo (
    period_start         date              NOT NULL,
    entity_key_lc        text              NOT NULL,
    qty_venduta_tot      numeric(12,3)     NOT NULL DEFAULT 0,
    imponibile_netto_tot numeric(12,2)     NOT NULL DEFAULT 0,
    qty_forecast_tot     numeric(12,3)
);


-- ============================================================
-- SECTION 7: DASHBOARD SALES TABLES (weekly, monthly, yearly)
-- Same 3-column schema for all three.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.t_dashboard_sales_weekly (
    period_start date          NOT NULL,
    qty_tot      numeric(18,3) NOT NULL DEFAULT 0,
    imp_tot      numeric(18,2) NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.t_dashboard_sales_monthly (
    period_start date          NOT NULL,
    qty_tot      numeric(18,3) NOT NULL DEFAULT 0,
    imp_tot      numeric(18,2) NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.t_dashboard_sales_yearly (
    period_start date          NOT NULL,
    qty_tot      numeric(18,3) NOT NULL DEFAULT 0,
    imp_tot      numeric(18,2) NOT NULL DEFAULT 0
);


-- ============================================================
-- SECTION 8: SEASONALITY TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS public.t_core_analytics__seasonality_month (
    entity_type      text          NOT NULL,
    entity_key_lc    text          NOT NULL,
    month_num        integer       NOT NULL,
    avg_qty_per_day  numeric(12,3) NOT NULL DEFAULT 0,
    sum_qty          numeric(14,3) NOT NULL DEFAULT 0,
    avg_rev_per_day  numeric(12,2) NOT NULL DEFAULT 0,
    sum_rev          numeric(14,2) NOT NULL DEFAULT 0,
    n_days           integer       NOT NULL DEFAULT 0
);


-- ============================================================
-- SECTION 9: CALENDAR EVENTS
-- Endpoint /planner/calendar-events already handles missing table
-- gracefully (returns empty list), but creating it prevents the
-- warning log and is cleaner.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.calendar_events (
    id           serial      PRIMARY KEY,
    date         date        NOT NULL,
    name         text        NOT NULL,
    impact_level text
);


-- ============================================================
-- SECTION 10: DAILY SERIES VIEWS (_lc suffix)
-- NOTE: These views reference t_core_analytics__* tables DIRECTLY.
-- In dev/Supabase these views reference an intermediate view which
-- references a materialized view which references the table.
-- For client-runtime we bypass that chain: t_table → _lc view.
-- The query result is identical.
-- ============================================================

CREATE OR REPLACE VIEW public.core_analytics__series_daily_famiglia_lc AS
    SELECT data,
           lower(entity_key)     AS entity_key_lc,
           qty_venduta_tot,
           imponibile_netto_tot,
           qty_forecast_tot,
           is_holiday,
           holiday_name,
           dow
      FROM public.t_core_analytics__series_daily_famiglia;

CREATE OR REPLACE VIEW public.core_analytics__series_daily_categoria_lc AS
    SELECT data,
           lower(entity_key)     AS entity_key_lc,
           qty_venduta_tot,
           imponibile_netto_tot,
           qty_forecast_tot,
           is_holiday,
           holiday_name,
           dow
      FROM public.t_core_analytics__series_daily_categoria;

CREATE OR REPLACE VIEW public.core_analytics__series_daily_fascia_lc AS
    SELECT data,
           lower(entity_key)     AS entity_key_lc,
           qty_venduta_tot,
           imponibile_netto_tot,
           qty_forecast_tot,
           is_holiday,
           holiday_name,
           dow
      FROM public.t_core_analytics__series_daily_fascia;

CREATE OR REPLACE VIEW public.core_analytics__series_daily_fascia_prezzo_lc AS
    SELECT data,
           lower(entity_key)     AS entity_key_lc,
           qty_venduta_tot,
           imponibile_netto_tot,
           qty_forecast_tot,
           is_holiday,
           holiday_name,
           dow
      FROM public.t_core_analytics__series_daily_fascia_prezzo;


-- ============================================================
-- SECTION 11: WEEKLY SERIES VIEWS (_lc suffix)
-- lower(btrim()) matches dev/Supabase behaviour exactly.
-- ============================================================

CREATE OR REPLACE VIEW public.core_analytics__series_weekly_famiglia_lc AS
    SELECT period_start          AS data,
           lower(btrim(entity_key)) AS entity_key_lc,
           qty_venduta_tot,
           imponibile_netto_tot,
           qty_forecast_tot
      FROM public.t_core_analytics__series_weekly_famiglia;

CREATE OR REPLACE VIEW public.core_analytics__series_weekly_categoria_lc AS
    SELECT period_start          AS data,
           lower(btrim(entity_key)) AS entity_key_lc,
           qty_venduta_tot,
           imponibile_netto_tot,
           qty_forecast_tot
      FROM public.t_core_analytics__series_weekly_categoria;

CREATE OR REPLACE VIEW public.core_analytics__series_weekly_fascia_lc AS
    SELECT period_start          AS data,
           lower(btrim(entity_key)) AS entity_key_lc,
           qty_venduta_tot,
           imponibile_netto_tot,
           qty_forecast_tot
      FROM public.t_core_analytics__series_weekly_fascia;

CREATE OR REPLACE VIEW public.core_analytics__series_weekly_fascia_prezzo_lc AS
    SELECT period_start          AS data,
           lower(btrim(entity_key)) AS entity_key_lc,
           qty_venduta_tot,
           imponibile_netto_tot,
           qty_forecast_tot
      FROM public.t_core_analytics__series_weekly_fascia_prezzo;


-- ============================================================
-- SECTION 12: MONTHLY SERIES VIEWS (_lc suffix)
-- ============================================================

CREATE OR REPLACE VIEW public.core_analytics__series_monthly_famiglia_lc AS
    SELECT period_start          AS data,
           lower(btrim(entity_key)) AS entity_key_lc,
           qty_venduta_tot,
           imponibile_netto_tot,
           qty_forecast_tot
      FROM public.t_core_analytics__series_monthly_famiglia;

CREATE OR REPLACE VIEW public.core_analytics__series_monthly_categoria_lc AS
    SELECT period_start          AS data,
           lower(btrim(entity_key)) AS entity_key_lc,
           qty_venduta_tot,
           imponibile_netto_tot,
           qty_forecast_tot
      FROM public.t_core_analytics__series_monthly_categoria;

CREATE OR REPLACE VIEW public.core_analytics__series_monthly_fascia_lc AS
    SELECT period_start          AS data,
           lower(btrim(entity_key)) AS entity_key_lc,
           qty_venduta_tot,
           imponibile_netto_tot,
           qty_forecast_tot
      FROM public.t_core_analytics__series_monthly_fascia;

CREATE OR REPLACE VIEW public.core_analytics__series_monthly_fascia_prezzo_lc AS
    SELECT period_start          AS data,
           lower(btrim(entity_key)) AS entity_key_lc,
           qty_venduta_tot,
           imponibile_netto_tot,
           qty_forecast_tot
      FROM public.t_core_analytics__series_monthly_fascia_prezzo;


-- ============================================================
-- SECTION 13: YEARLY SERIES VIEWS (_lc suffix)
-- entity_key_lc is already lowercased in the t_ table — no lower() needed.
-- ============================================================

CREATE OR REPLACE VIEW public.core_analytics__series_yearly_famiglia_lc AS
    SELECT period_start      AS data,
           entity_key_lc,
           qty_venduta_tot,
           imponibile_netto_tot,
           qty_forecast_tot
      FROM public.t_core_analytics__series_yearly_famiglia;

CREATE OR REPLACE VIEW public.core_analytics__series_yearly_categoria_lc AS
    SELECT period_start      AS data,
           entity_key_lc,
           qty_venduta_tot,
           imponibile_netto_tot,
           qty_forecast_tot
      FROM public.t_core_analytics__series_yearly_categoria;

CREATE OR REPLACE VIEW public.core_analytics__series_yearly_fascia_lc AS
    SELECT period_start      AS data,
           entity_key_lc,
           qty_venduta_tot,
           imponibile_netto_tot,
           qty_forecast_tot
      FROM public.t_core_analytics__series_yearly_fascia;

CREATE OR REPLACE VIEW public.core_analytics__series_yearly_fascia_prezzo_lc AS
    SELECT period_start      AS data,
           entity_key_lc,
           qty_venduta_tot,
           imponibile_netto_tot,
           qty_forecast_tot
      FROM public.t_core_analytics__series_yearly_fascia_prezzo;


-- ============================================================
-- SECTION 14: DASHBOARD SALES VIEWS
-- ============================================================

CREATE OR REPLACE VIEW public.dashboard__sales_weekly AS
    SELECT period_start AS data,
           qty_tot,
           imp_tot
      FROM public.t_dashboard_sales_weekly;

CREATE OR REPLACE VIEW public.dashboard__sales_monthly AS
    SELECT period_start AS data,
           qty_tot,
           imp_tot
      FROM public.t_dashboard_sales_monthly;

CREATE OR REPLACE VIEW public.dashboard__sales_yearly AS
    SELECT period_start AS data,
           qty_tot,
           imp_tot
      FROM public.t_dashboard_sales_yearly;


-- ============================================================
-- SECTION 15: SEASONALITY VIEW
-- ============================================================

CREATE OR REPLACE VIEW public.core_analytics__seasonality_month AS
    SELECT entity_type,
           entity_key_lc,
           month_num,
           avg_qty_per_day,
           sum_qty,
           avg_rev_per_day,
           sum_rev,
           n_days
      FROM public.t_core_analytics__seasonality_month;


-- ============================================================
-- END OF WAVE 7B.1 SCHEMA
-- Object counts:
--   Tables:  23  (sections 1-9)
--   Views:   20  (sections 10-15)
--   Total:   43
-- ============================================================
