-- GreenBrain Client Runtime — Wave 7B.2-F Series Breakdown
--
-- STATUS: PLANNED
--
-- Scope: exactly 1 endpoint:
--   /api/v1/analytics/series-breakdown
--
-- Query params required by analytics.py:
--   - entity_type: famiglia | categoria | fascia
--   - granularity: day | week | month | year
--   - entity_key
--   - date_from
--   - date_to
--
-- Backend mapping:
--   _breakdown_view(gran_db, entity_type) =>
--     core_analytics__breakdown_{gran_db}_{entity_type}_fp_v2
--
-- Objects:
--   12 tables
--   12 views
--
-- No functions. No extensions. No matviews. No Supabase-specific schemas.
-- Thin wrappers only: each view selects from its corresponding t_* table.
--
-- Expected result with empty tables:
--   HTTP 200 with {"count":0,"items":[]}

SET search_path = public;

-- ============================================================
-- DAILY TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.t_core_analytics__breakdown_daily_famiglia_fp_v2 (
    data date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    is_holiday boolean DEFAULT false NOT NULL,
    holiday_name text,
    dow integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__breakdown_daily_categoria_fp_v2 (
    data date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    is_holiday boolean DEFAULT false NOT NULL,
    holiday_name text,
    dow integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__breakdown_daily_fascia_fp_v2 (
    data date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    is_holiday boolean DEFAULT false NOT NULL,
    holiday_name text,
    dow integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

-- ============================================================
-- WEEKLY TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.t_core_analytics__breakdown_weekly_famiglia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__breakdown_weekly_categoria_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__breakdown_weekly_fascia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

-- ============================================================
-- MONTHLY TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.t_core_analytics__breakdown_monthly_famiglia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__breakdown_monthly_categoria_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__breakdown_monthly_fascia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

-- ============================================================
-- YEARLY TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.t_core_analytics__breakdown_yearly_famiglia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__breakdown_yearly_categoria_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

CREATE TABLE IF NOT EXISTS public.t_core_analytics__breakdown_yearly_fascia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);

-- ============================================================
-- DAILY VIEWS
-- ============================================================

CREATE OR REPLACE VIEW public.core_analytics__breakdown_daily_famiglia_fp_v2 AS
SELECT
    data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast,
    dow,
    is_holiday,
    holiday_name
FROM public.t_core_analytics__breakdown_daily_famiglia_fp_v2;

CREATE OR REPLACE VIEW public.core_analytics__breakdown_daily_categoria_fp_v2 AS
SELECT
    data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast,
    dow,
    is_holiday,
    holiday_name
FROM public.t_core_analytics__breakdown_daily_categoria_fp_v2;

CREATE OR REPLACE VIEW public.core_analytics__breakdown_daily_fascia_fp_v2 AS
SELECT
    data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast,
    dow,
    is_holiday,
    holiday_name
FROM public.t_core_analytics__breakdown_daily_fascia_fp_v2;

-- ============================================================
-- WEEKLY VIEWS
-- ============================================================

CREATE OR REPLACE VIEW public.core_analytics__breakdown_weekly_famiglia_fp_v2 AS
SELECT
    period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
FROM public.t_core_analytics__breakdown_weekly_famiglia_fp_v2;

CREATE OR REPLACE VIEW public.core_analytics__breakdown_weekly_categoria_fp_v2 AS
SELECT
    period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
FROM public.t_core_analytics__breakdown_weekly_categoria_fp_v2;

CREATE OR REPLACE VIEW public.core_analytics__breakdown_weekly_fascia_fp_v2 AS
SELECT
    period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
FROM public.t_core_analytics__breakdown_weekly_fascia_fp_v2;

-- ============================================================
-- MONTHLY VIEWS
-- ============================================================

CREATE OR REPLACE VIEW public.core_analytics__breakdown_monthly_famiglia_fp_v2 AS
SELECT
    period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
FROM public.t_core_analytics__breakdown_monthly_famiglia_fp_v2;

CREATE OR REPLACE VIEW public.core_analytics__breakdown_monthly_categoria_fp_v2 AS
SELECT
    period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
FROM public.t_core_analytics__breakdown_monthly_categoria_fp_v2;

CREATE OR REPLACE VIEW public.core_analytics__breakdown_monthly_fascia_fp_v2 AS
SELECT
    period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
FROM public.t_core_analytics__breakdown_monthly_fascia_fp_v2;

-- ============================================================
-- YEARLY VIEWS
-- ============================================================

CREATE OR REPLACE VIEW public.core_analytics__breakdown_yearly_famiglia_fp_v2 AS
SELECT
    period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
FROM public.t_core_analytics__breakdown_yearly_famiglia_fp_v2;

CREATE OR REPLACE VIEW public.core_analytics__breakdown_yearly_categoria_fp_v2 AS
SELECT
    period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
FROM public.t_core_analytics__breakdown_yearly_categoria_fp_v2;

CREATE OR REPLACE VIEW public.core_analytics__breakdown_yearly_fascia_fp_v2 AS
SELECT
    period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
FROM public.t_core_analytics__breakdown_yearly_fascia_fp_v2;
