-- GreenBrain analytics patch
-- Adds articolo historical series views and extends future window KPI to articolo.

CREATE OR REPLACE VIEW public.core_analytics__series_daily_articolo_lc AS
SELECT
  data::date AS data,
  lower(btrim(codart::text)) AS entity_key_lc,
  SUM(COALESCE(qty_venduta, 0))::numeric AS qty_venduta_tot,
  SUM(COALESCE(imponibile_netto, 0))::numeric AS imponibile_netto_tot,
  SUM(COALESCE(qty_forecast, 0))::numeric AS qty_forecast_tot,
  BOOL_OR(COALESCE(is_holiday, false)) AS is_holiday,
  MAX(holiday_name) AS holiday_name,
  MAX(dow)::int AS dow
FROM public.core_analytics__article_sales_daily
WHERE codart IS NOT NULL
GROUP BY data::date, lower(btrim(codart::text));

CREATE OR REPLACE VIEW public.core_analytics__series_weekly_articolo_lc AS
SELECT
  date_trunc('week', data::timestamp with time zone)::date AS data,
  lower(btrim(codart::text)) AS entity_key_lc,
  SUM(COALESCE(qty_venduta, 0))::numeric AS qty_venduta_tot,
  SUM(COALESCE(imponibile_netto, 0))::numeric AS imponibile_netto_tot,
  SUM(COALESCE(qty_forecast, 0))::numeric AS qty_forecast_tot
FROM public.core_analytics__article_sales_daily
WHERE codart IS NOT NULL
GROUP BY date_trunc('week', data::timestamp with time zone)::date, lower(btrim(codart::text));

CREATE OR REPLACE VIEW public.core_analytics__series_monthly_articolo_lc AS
SELECT
  date_trunc('month', data::timestamp with time zone)::date AS data,
  lower(btrim(codart::text)) AS entity_key_lc,
  SUM(COALESCE(qty_venduta, 0))::numeric AS qty_venduta_tot,
  SUM(COALESCE(imponibile_netto, 0))::numeric AS imponibile_netto_tot,
  SUM(COALESCE(qty_forecast, 0))::numeric AS qty_forecast_tot
FROM public.core_analytics__article_sales_daily
WHERE codart IS NOT NULL
GROUP BY date_trunc('month', data::timestamp with time zone)::date, lower(btrim(codart::text));

CREATE OR REPLACE VIEW public.core_analytics__series_yearly_articolo_lc AS
SELECT
  date_trunc('year', data::timestamp with time zone)::date AS data,
  lower(btrim(codart::text)) AS entity_key_lc,
  SUM(COALESCE(qty_venduta, 0))::numeric AS qty_venduta_tot,
  SUM(COALESCE(imponibile_netto, 0))::numeric AS imponibile_netto_tot,
  SUM(COALESCE(qty_forecast, 0))::numeric AS qty_forecast_tot
FROM public.core_analytics__article_sales_daily
WHERE codart IS NOT NULL
GROUP BY date_trunc('year', data::timestamp with time zone)::date, lower(btrim(codart::text));
CREATE OR REPLACE FUNCTION public.core_analytics__future_window_stats_v2(p_entity_type text, p_entity_key text, p_anchor_to date DEFAULT CURRENT_DATE, p_windows integer[] DEFAULT ARRAY[7, 14, 30, 60])
 RETURNS TABLE(window_days integer, min_qty numeric, max_qty numeric, avg_qty numeric)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  m int := extract(month from p_anchor_to)::int;
  d int := extract(day from p_anchor_to)::int;
BEGIN
  RETURN QUERY
  WITH years AS (
    SELECT generate_series(
      extract(year from (p_anchor_to - interval '20 years'))::int,
      extract(year from p_anchor_to)::int - 1
    ) AS y
  ),
  starts AS (
    SELECT
      y,
      (
        make_date(y, m, 1)
        + (
          least(
            d,
            extract(day from (date_trunc('month', make_date(y,m,1)) + interval '1 month - 1 day'))::int
          ) - 1
        ) * interval '1 day'
      )::date AS start_date
    FROM years
  ),
  w AS (
    SELECT unnest(p_windows)::int AS window_days
  ),
  base AS (
    SELECT
      w.window_days,
      s.y,
      (
        CASE
          WHEN p_entity_type = 'famiglia' THEN (
            SELECT coalesce(sum(qty_venduta_tot),0)
            FROM public.t_core_analytics__series_daily_famiglia t
            WHERE lower(t.entity_key) = lower(p_entity_key)
              AND t.data > s.start_date
              AND t.data <= s.start_date + (w.window_days * interval '1 day')
          )
          WHEN p_entity_type = 'categoria' THEN (
            SELECT coalesce(sum(qty_venduta_tot),0)
            FROM public.mv_core_analytics__series_daily_categoria t
            WHERE lower(t.entity_key) = lower(p_entity_key)
              AND t.data > s.start_date
              AND t.data <= s.start_date + (w.window_days * interval '1 day')
          )
          WHEN p_entity_type = 'fascia' THEN (
            SELECT coalesce(sum(qty_venduta_tot),0)
            FROM public.mv_core_analytics__series_daily_fascia t
            WHERE lower(t.entity_key) = lower(p_entity_key)
              AND t.data > s.start_date
              AND t.data <= s.start_date + (w.window_days * interval '1 day')
          )
          WHEN p_entity_type = 'fascia_prezzo' THEN (
            SELECT coalesce(sum(qty_venduta_tot),0)
            FROM public.mv_core_analytics__series_daily_fascia_prezzo t
            WHERE lower(t.entity_key) = lower(p_entity_key)
              AND t.data > s.start_date
              AND t.data <= s.start_date + (w.window_days * interval '1 day')
          )
          WHEN p_entity_type = 'articolo' THEN (
            SELECT coalesce(sum(qty_venduta),0)
            FROM public.core_analytics__article_sales_daily t
            WHERE lower(trim(t.codart)) = lower(trim(p_entity_key))
              AND t.data > s.start_date
              AND t.data <= s.start_date + (w.window_days * interval '1 day')
          )
          ELSE 0
        END
      )::numeric AS qty
    FROM starts s
    CROSS JOIN w
  )
  SELECT
    base.window_days,
    min(base.qty) AS min_qty,
    max(base.qty) AS max_qty,
    avg(base.qty) AS avg_qty
  FROM base
  GROUP BY base.window_days
  ORDER BY base.window_days;
END
$function$

