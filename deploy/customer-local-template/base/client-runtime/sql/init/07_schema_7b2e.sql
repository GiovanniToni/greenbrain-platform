-- GreenBrain Client Runtime — Wave 7B.2-E Compare Series
--
-- Scope: exactly 1 endpoint:
--   /api/v1/analytics/compare-series
--
-- Objects:
--   1 table  : greenhouse_forecast_features_dense
--   2 views  : core_analytics__series_daily, core_analytics__series_daily_total
--
-- No functions. No extensions. No matviews. No Supabase-specific schemas.

SET search_path = public;

-- ============================================================
-- SECTION 1: TABLE — greenhouse_forecast_features_dense
-- Root table required by core_analytics__series_daily
-- ============================================================

CREATE TABLE IF NOT EXISTS public.greenhouse_forecast_features_dense (
    data date NOT NULL,
    famiglia text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(12,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(12,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    fascia_corretta text,
    categoria_corretta text,
    pot_sizes_text text,
    pot_sizes_json jsonb DEFAULT '[]'::jsonb NOT NULL,
    articoli_inclusi text,
    articoli_json jsonb DEFAULT '[]'::jsonb NOT NULL,
    tmin_c numeric(5,2),
    tmax_c numeric(5,2),
    tavg_c numeric(5,2),
    rain_mm numeric(7,2),
    sun_hours numeric(5,2),
    is_holiday boolean DEFAULT false NOT NULL,
    holiday_name text,
    dow integer,
    week_num integer,
    month_num integer,
    year_num integer,
    qty_lag_1 numeric(12,3),
    qty_lag_2 numeric(12,3),
    qty_lag_3 numeric(12,3),
    qty_lag_7 numeric(12,3),
    qty_lag_10 numeric(12,3),
    qty_lag_14 numeric(12,3),
    qty_ma_3 numeric(18,10),
    qty_ma_7 numeric(18,10),
    qty_ma_10 numeric(18,10),
    qty_ma_14 numeric(18,10),
    qty_ma_28 numeric(18,10),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL
);

-- ============================================================
-- SECTION 2: VIEW — core_analytics__series_daily
-- Extracted from current-schema.sql
-- ============================================================

CREATE OR REPLACE VIEW public.core_analytics__series_daily AS
 SELECT f.data,
    f.famiglia,
    f.fascia_corretta,
    f.categoria_corretta,
    f.fascia_prezzo_iva_inc,
    f.qty_venduta,
    f.imponibile_netto_tot,
    f.num_articoli,
    COALESCE(f.is_holiday, false) AS is_holiday,
    f.holiday_name,
    f.dow,
    f.week_num,
    f.month_num,
    f.year_num,
    fc.qty_forecast
   FROM (public.greenhouse_forecast_features_dense f
     LEFT JOIN public.greenhouse_forecast_results_v2 fc
       ON ((fc.data = f.data)
       AND (lower(fc.famiglia) = lower(f.famiglia))
       AND (fc.fascia_prezzo_iva_inc = f.fascia_prezzo_iva_inc)));

-- ============================================================
-- SECTION 3: VIEW — core_analytics__series_daily_total
-- Extracted from current-schema.sql
-- ============================================================

CREATE OR REPLACE VIEW public.core_analytics__series_daily_total AS
 SELECT data,
    famiglia,
    categoria_corretta,
    fascia_corretta,
    fascia_prezzo_iva_inc,
    sum(qty_venduta) AS qty_venduta_tot,
    sum(imponibile_netto_tot) AS imponibile_netto_tot,
    sum(num_articoli) AS num_articoli,
    bool_or(is_holiday) AS is_holiday,
    max(holiday_name) AS holiday_name,
    max(dow) AS dow,
    max(week_num) AS week_num,
    max(month_num) AS month_num,
    max(year_num) AS year_num,
    sum(COALESCE(qty_forecast, (0)::numeric)) AS qty_forecast_tot
   FROM public.core_analytics__series_daily
  GROUP BY data, famiglia, categoria_corretta, fascia_corretta, fascia_prezzo_iva_inc;
