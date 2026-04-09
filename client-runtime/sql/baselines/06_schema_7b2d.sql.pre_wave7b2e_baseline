-- GreenBrain Client Runtime — Wave 7B.2-D Future Windows Stats
--
-- STATUS: PLANNED
--
-- Scope: exactly 1 endpoint:
--   /api/v1/analytics/future-windows-stats
--
-- Object count:
--   3 views
--   1 function
--
-- Rationale:
-- The backend calls public.core_analytics__future_window_stats_v2(...).
-- That function references:
--   - public.t_core_analytics__series_daily_famiglia
--   - public.mv_core_analytics__series_daily_categoria
--   - public.mv_core_analytics__series_daily_fascia
--   - public.mv_core_analytics__series_daily_fascia_prezzo
--
-- In client-runtime, the four t_core_analytics__series_daily_* tables already exist
-- from Wave 7B.1, but the three mv_* objects do not.
-- So this wave adds 3 compatibility views over the existing t_* tables,
-- then installs the function body as extracted from current-schema.sql.
--
-- No new tables. No extensions. No matviews. No Supabase-specific syntax.

SET search_path = public;

-- ============================================================
-- SECTION 1: compatibility views required by
-- core_analytics__future_window_stats_v2
-- ============================================================

CREATE OR REPLACE VIEW public.mv_core_analytics__series_daily_categoria AS
SELECT *
FROM public.t_core_analytics__series_daily_categoria;

CREATE OR REPLACE VIEW public.mv_core_analytics__series_daily_fascia AS
SELECT *
FROM public.t_core_analytics__series_daily_fascia;

CREATE OR REPLACE VIEW public.mv_core_analytics__series_daily_fascia_prezzo AS
SELECT *
FROM public.t_core_analytics__series_daily_fascia_prezzo;

-- ============================================================
-- SECTION 2: function
-- Extracted from sql/schema/current-schema.sql
-- ============================================================

CREATE OR REPLACE FUNCTION public.core_analytics__future_window_stats_v2(
    p_entity_type text,
    p_entity_key text,
    p_anchor_to date DEFAULT CURRENT_DATE,
    p_windows integer[] DEFAULT ARRAY[7, 14, 30, 60]
) RETURNS TABLE(
    window_days integer,
    min_qty numeric,
    max_qty numeric,
    avg_qty numeric
)
LANGUAGE plpgsql STABLE
AS $$declare
  m int := extract(month from p_anchor_to)::int;
  d int := extract(day from p_anchor_to)::int;
begin
  return query
  with years as (
    select generate_series(
      extract(year from (p_anchor_to - interval '20 years'))::int,
      extract(year from p_anchor_to)::int - 1
    ) as y
  ),
  starts as (
    select
      y,
      (
        make_date(y, m, 1)
        + (
            least(
              d,
              extract(day from (date_trunc('month', make_date(y,m,1)) + interval '1 month - 1 day'))::int
            ) - 1
          ) * interval '1 day'
      )::date as start_date
    from years
  ),
  w as (
    select unnest(p_windows)::int as window_days
  ),
  base as (
    select
      w.window_days,
      s.y,
      (
        case
          when p_entity_type = 'famiglia' then (
            select coalesce(sum(qty_venduta_tot),0)
            from public.t_core_analytics__series_daily_famiglia t
            where lower(t.entity_key) = lower(p_entity_key)
              and t.data > s.start_date
              and t.data <= s.start_date + (w.window_days * interval '1 day')
          )
          when p_entity_type = 'categoria' then (
            select coalesce(sum(qty_venduta_tot),0)
            from public.mv_core_analytics__series_daily_categoria t
            where lower(t.entity_key) = lower(p_entity_key)
              and t.data > s.start_date
              and t.data <= s.start_date + (w.window_days * interval '1 day')
          )
          when p_entity_type = 'fascia' then (
            select coalesce(sum(qty_venduta_tot),0)
            from public.mv_core_analytics__series_daily_fascia t
            where lower(t.entity_key) = lower(p_entity_key)
              and t.data > s.start_date
              and t.data <= s.start_date + (w.window_days * interval '1 day')
          )
          when p_entity_type = 'fascia_prezzo' then (
            select coalesce(sum(qty_venduta_tot),0)
            from public.mv_core_analytics__series_daily_fascia_prezzo t
            where lower(t.entity_key) = lower(p_entity_key)
              and t.data > s.start_date
              and t.data <= s.start_date + (w.window_days * interval '1 day')
          )
          else 0
        end
      )::numeric as qty
    from starts s
    cross join w
  )
  select
    base.window_days as window_days,
    min(base.qty) as min_qty,
    max(base.qty) as max_qty,
    avg(base.qty) as avg_qty
  from base
  group by base.window_days
  order by base.window_days;
end$$;

-- ============================================================
-- END OF WAVE 7B.2-D
-- Object counts:
--   views: 3
--   functions: 1
-- ============================================================
