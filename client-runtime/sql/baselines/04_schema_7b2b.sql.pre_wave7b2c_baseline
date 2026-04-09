-- GreenBrain Client Runtime — Wave 7B.2-B Analytics Functions: range-totals + stock-and-reorder
--
-- STATUS: PLANNED — not yet applied to client-runtime postgres
--
-- Scope: exactly 2 analytics endpoints:
--   /api/v1/analytics/range-totals      → core_analytics__range_totals_v2()
--   /api/v1/analytics/stock-and-reorder → core_analytics__stock_and_reorder_v1()
--
-- Object count: 10
--   2 tables    (greenhouse_stock_raw_upload, greenhouse_sales_family_daily_fact)
--   6 views     (stock_enriched, forecast_windows, stock_family_latest,
--                sales_family_meta, order_suggestions_v2, order_suggestions_enriched_v2)
--   2 functions (core_analytics__range_totals_v2, core_analytics__stock_and_reorder_v1)
--
-- Prerequisites (must already exist before applying this file):
--   Wave 7B.1:   greenhouse_forecast_results_v2, core_analytics__series_daily_*_lc views (x4)
--   Wave 7B.2-A: greenhouse_products_normalized
--
-- No new extensions required.
-- No matviews. No Supabase-specific syntax. No cross-schema references.
--
-- ARTICOLO branch note:
--   core_analytics__range_totals_v2 contains an internal ARTICOLO branch that
--   references public.core_analytics__article_sales_daily.  That branch is never
--   reached from the backend: analytics.py calls _resolve_entity() which raises
--   HTTP 400 for entity_type='articolo' before the RPC is invoked.
--   plpgsql functions validate SQL at execution time, not at CREATE time, so the
--   function creates successfully without core_analytics__article_sales_daily existing.
--   That view is deferred to a later wave.
--
-- Dependency graph for this wave (all chains terminate at existing objects):
--
--   core_analytics__range_totals_v2
--     → core_analytics__series_daily_{famiglia,categoria,fascia,fascia_prezzo}_lc  [7B.1 ✅]
--
--   core_analytics__stock_and_reorder_v1
--     → greenhouse_stock_raw_upload                     [this wave]
--     → greenhouse_stock_enriched                       [this wave]
--         → greenhouse_stock_raw_upload                 [this wave]
--         → greenhouse_products_normalized              [7B.2-A ✅]
--     → greenhouse_forecast_windows_v2                  [this wave]
--         → greenhouse_forecast_results_v2              [7B.1 ✅]
--     → greenhouse_stock_family_latest_v2               [this wave]
--         → greenhouse_stock_enriched                   [this wave]
--     → greenhouse_sales_family_daily_fact              [this wave]
--     → greenhouse_sales_family_meta_v2                 [this wave]
--         → greenhouse_sales_family_daily_fact          [this wave]
--     → greenhouse_order_suggestions_v2                 [this wave]
--         → greenhouse_forecast_windows_v2              [this wave]
--         → greenhouse_stock_family_latest_v2           [this wave]
--     → greenhouse_order_suggestions_enriched_v2        [this wave]
--         → greenhouse_order_suggestions_v2             [this wave]
--         → greenhouse_sales_family_meta_v2             [this wave]
--
-- All function bodies extracted VERBATIM from sql/schema/current-schema.sql.
-- All view definitions extracted VERBATIM.
-- Table schemas verified against sql/schema/current-schema.sql.
--

SET search_path = public;


-- ============================================================
-- SECTION 1: TABLE — greenhouse_stock_raw_upload
-- Raw stock upload from POS/warehouse.
-- Used by: greenhouse_stock_enriched, greenhouse_stock_family_latest_v2
-- Schema verified against current-schema.sql.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.greenhouse_stock_raw_upload (
    data_rilevazione date    NOT NULL DEFAULT CURRENT_DATE,
    codart           text    NOT NULL,
    descrizione      text,
    qty_giacenza     numeric(12,3) NOT NULL,
    created_at       timestamp without time zone DEFAULT now(),
    CONSTRAINT greenhouse_stock_raw_upload_pkey PRIMARY KEY (data_rilevazione, codart)
);


-- ============================================================
-- SECTION 2: VIEW — greenhouse_stock_enriched
-- Joins stock upload with product catalog to add hierarchy columns.
-- Used by: greenhouse_stock_family_latest_v2, stock_and_reorder_v1
-- Extracted verbatim from current-schema.sql.
-- ============================================================

CREATE OR REPLACE VIEW public.greenhouse_stock_enriched AS
    SELECT s.data_rilevazione,
           s.codart,
           s.descrizione      AS descrizione_stock,
           s.qty_giacenza,
           p.famiglia,
           p.fascia_prezzo_iva_inc,
           p.pot_size,
           p.fascia_corretta,
           p.categoria_corretta
      FROM public.greenhouse_stock_raw_upload s
      LEFT JOIN public.greenhouse_products_normalized p
             ON s.codart = p.codart::text;


-- ============================================================
-- SECTION 3: VIEW — greenhouse_forecast_windows_v2
-- Aggregates next-3-day and next-4-to-10-day forecast demand
-- from greenhouse_forecast_results_v2 (already in Wave 7B.1).
-- Used by: greenhouse_order_suggestions_v2
-- Extracted verbatim from current-schema.sql.
-- ============================================================

CREATE OR REPLACE VIEW public.greenhouse_forecast_windows_v2 AS
    SELECT famiglia,
           fascia_prezzo_iva_inc,
           sum(CASE
                   WHEN data >= (CURRENT_DATE + '1 day'::interval)
                    AND data <= (CURRENT_DATE + '3 days'::interval)
                   THEN qty_forecast
                   ELSE 0
               END) AS qty_forecast_1_3,
           sum(CASE
                   WHEN data >= (CURRENT_DATE + '4 days'::interval)
                    AND data <= (CURRENT_DATE + '10 days'::interval)
                   THEN qty_forecast
                   ELSE 0
               END) AS qty_forecast_4_10
      FROM public.greenhouse_forecast_results_v2
     GROUP BY famiglia, fascia_prezzo_iva_inc;


-- ============================================================
-- SECTION 4: VIEW — greenhouse_stock_family_latest_v2
-- Latest stock snapshot aggregated to famiglia+fascia_prezzo level.
-- Used by: greenhouse_order_suggestions_v2
-- Extracted verbatim from current-schema.sql.
-- ============================================================

CREATE OR REPLACE VIEW public.greenhouse_stock_family_latest_v2 AS
    WITH latest_date AS (
        SELECT max(s.data_rilevazione) AS data_rilevazione
          FROM public.greenhouse_stock_raw_upload s
    )
    SELECT e.data_rilevazione,
           e.famiglia,
           e.fascia_prezzo_iva_inc,
           sum(e.qty_giacenza) AS qty_giacenza
      FROM public.greenhouse_stock_enriched e
      JOIN latest_date ld ON e.data_rilevazione = ld.data_rilevazione
     WHERE e.famiglia IS NOT NULL
       AND e.fascia_prezzo_iva_inc IS NOT NULL
     GROUP BY e.data_rilevazione, e.famiglia, e.fascia_prezzo_iva_inc
     ORDER BY e.famiglia, e.fascia_prezzo_iva_inc;


-- ============================================================
-- SECTION 5: TABLE — greenhouse_sales_family_daily_fact
-- Aggregated daily sales fact table at famiglia+fascia_prezzo level.
-- Used by: greenhouse_sales_family_meta_v2
-- Schema verified against current-schema.sql (12 columns).
-- ============================================================

CREATE TABLE IF NOT EXISTS public.greenhouse_sales_family_daily_fact (
    data                 date          NOT NULL,
    famiglia             text          NOT NULL,
    fascia_prezzo_iva_inc text         NOT NULL,
    qty_venduta          numeric(12,3) NOT NULL DEFAULT 0,
    imponibile_netto_tot numeric(12,2) NOT NULL DEFAULT 0,
    num_articoli         integer       NOT NULL DEFAULT 0,
    fascia_corretta      text,
    categoria_corretta   text,
    pot_sizes_text       text,
    pot_sizes_json       jsonb         NOT NULL DEFAULT '[]'::jsonb,
    articoli_inclusi     text,
    articoli_json        jsonb         NOT NULL DEFAULT '[]'::jsonb
);


-- ============================================================
-- SECTION 6: VIEW — greenhouse_sales_family_meta_v2
-- Derives hierarchy metadata (fascia, categoria, pot_sizes)
-- for each famiglia+fascia_prezzo from the sales fact table.
-- Used by: greenhouse_order_suggestions_enriched_v2
-- Extracted verbatim from current-schema.sql.
-- ============================================================

CREATE OR REPLACE VIEW public.greenhouse_sales_family_meta_v2 AS
    SELECT famiglia,
           fascia_prezzo_iva_inc,
           min(fascia_corretta)  AS fascia_corretta,
           min(categoria_corretta) AS categoria_corretta,
           string_agg(DISTINCT ps, ',' ORDER BY ps) AS pot_sizes_text,
           jsonb_agg(DISTINCT ps)                   AS pot_sizes_json
      FROM (
           SELECT greenhouse_sales_family_daily_fact.famiglia,
                  greenhouse_sales_family_daily_fact.fascia_prezzo_iva_inc,
                  greenhouse_sales_family_daily_fact.fascia_corretta,
                  greenhouse_sales_family_daily_fact.categoria_corretta,
                  jsonb_array_elements_text(
                      greenhouse_sales_family_daily_fact.pot_sizes_json
                  ) AS ps
             FROM public.greenhouse_sales_family_daily_fact
           ) x
     GROUP BY famiglia, fascia_prezzo_iva_inc;


-- ============================================================
-- SECTION 7: VIEW — greenhouse_order_suggestions_v2
-- Computes reorder quantities from forecast windows + latest stock.
-- Used by: greenhouse_order_suggestions_enriched_v2, stock_and_reorder_v1
-- Extracted verbatim from current-schema.sql.
-- ============================================================

CREATE OR REPLACE VIEW public.greenhouse_order_suggestions_v2 AS
    WITH stock AS (
        SELECT greenhouse_stock_family_latest_v2.data_rilevazione,
               greenhouse_stock_family_latest_v2.famiglia,
               greenhouse_stock_family_latest_v2.fascia_prezzo_iva_inc,
               greenhouse_stock_family_latest_v2.qty_giacenza
          FROM public.greenhouse_stock_family_latest_v2
    ),
    params AS (
        SELECT 1.5 AS safety_factor
    )
    SELECT f.famiglia,
           f.fascia_prezzo_iva_inc,
           f.qty_forecast_1_3  AS demand_lead,
           f.qty_forecast_4_10 AS demand_cycle,
           CASE
               WHEN s.famiglia IS NULL THEN false
               ELSE true
           END AS in_assortimento,
           coalesce(s.qty_giacenza, 0)                          AS qty_giacenza,
           coalesce(s.qty_giacenza, 0) - f.qty_forecast_1_3    AS stock_after_lead_raw,
           greatest(0, coalesce(s.qty_giacenza, 0) - f.qty_forecast_1_3) AS stock_after_lead,
           f.qty_forecast_4_10 * p.safety_factor               AS required_on_arrival,
           greatest(0,
               f.qty_forecast_4_10 * p.safety_factor
               - greatest(0, coalesce(s.qty_giacenza, 0) - f.qty_forecast_1_3)
           )                                                    AS qty_da_ordinare,
           CASE
               WHEN coalesce(s.qty_giacenza, 0) < f.qty_forecast_1_3 THEN true
               ELSE false
           END AS rischio_stockout_prima_di_arrivo
      FROM public.greenhouse_forecast_windows_v2 f
      LEFT JOIN stock s
             ON f.famiglia = s.famiglia::text
            AND f.fascia_prezzo_iva_inc = s.fascia_prezzo_iva_inc::text
      CROSS JOIN params p
     ORDER BY f.famiglia, f.fascia_prezzo_iva_inc;


-- ============================================================
-- SECTION 8: VIEW — greenhouse_order_suggestions_enriched_v2
-- Enriches order suggestions with hierarchy metadata.
-- Used by: stock_and_reorder_v1, planner endpoints (deferred)
-- Extracted verbatim from current-schema.sql.
-- ============================================================

CREATE OR REPLACE VIEW public.greenhouse_order_suggestions_enriched_v2 AS
    SELECT o.famiglia,
           o.fascia_prezzo_iva_inc,
           o.demand_lead,
           o.demand_cycle,
           o.in_assortimento,
           o.qty_giacenza,
           o.stock_after_lead_raw,
           o.stock_after_lead,
           o.required_on_arrival,
           o.qty_da_ordinare,
           o.rischio_stockout_prima_di_arrivo,
           m.fascia_corretta,
           m.categoria_corretta,
           m.pot_sizes_text,
           m.pot_sizes_json
      FROM public.greenhouse_order_suggestions_v2 o
      LEFT JOIN public.greenhouse_sales_family_meta_v2 m
             ON o.famiglia = m.famiglia
            AND o.fascia_prezzo_iva_inc = m.fascia_prezzo_iva_inc
     WHERE o.qty_da_ordinare >= 1
     ORDER BY o.famiglia, o.fascia_prezzo_iva_inc;


-- ============================================================
-- SECTION 9: FUNCTION — core_analytics__range_totals_v2
-- Returns aggregated sales totals for an entity + date range.
-- Dependencies: core_analytics__series_daily_*_lc (ALL in Wave 7B.1)
--
-- ARTICOLO branch note: this function body includes a branch for
-- entity_type='articolo' that references core_analytics__article_sales_daily.
-- That branch is unreachable from the backend (analytics.py blocks 'articolo'
-- before the RPC call with a 400 response). plpgsql validates SQL at execution
-- time per branch, not at CREATE time, so this function creates successfully.
-- core_analytics__article_sales_daily is deferred to a later wave.
--
-- Extracted VERBATIM from sql/schema/current-schema.sql.
-- ============================================================

CREATE OR REPLACE FUNCTION public.core_analytics__range_totals_v2(
    p_entity_type text,
    p_entity_key  text,
    p_date_from   date,
    p_date_to     date
)
RETURNS TABLE(
    qty_tot      numeric,
    imp_tot      numeric,
    days         integer,
    active_days  integer,
    zero_days    integer,
    min_day      date,
    min_qty      numeric,
    max_day      date,
    max_qty      numeric
)
LANGUAGE plpgsql STABLE
AS $$
declare
  v_type text := lower(btrim(p_entity_type::text));
  v_key  text := lower(btrim(p_entity_key::text));
begin
  if v_type is null or v_type = '' then
    raise exception 'p_entity_type is required (got=%)', p_entity_type;
  end if;

  if p_entity_key is null or btrim(p_entity_key::text) = '' then
    raise exception 'p_entity_key is required';
  end if;

  -- Normalizza eventuali sinonimi (opzionale)
  if v_type in ('family') then v_type := 'famiglia'; end if;
  if v_type in ('category') then v_type := 'categoria'; end if;
  if v_type in ('band','range') then v_type := 'fascia'; end if;
  if v_type in ('price_band','fascia-prezzo','fascia prezzo') then v_type := 'fascia_prezzo'; end if;

  -- ARTICOLO (codart case-sensitive: NON loweriamo la chiave)
  if v_type = 'articolo' then
    return query
    with r as (
      select
        data::date as data,
        qty_venduta::numeric as qty,
        imponibile_netto::numeric as imp
      from public.core_analytics__article_sales_daily
      where codart = btrim(p_entity_key::text)
        and data between p_date_from and p_date_to
    )
    select
      coalesce(sum(r.qty),0) as qty_tot,
      coalesce(sum(r.imp),0) as imp_tot,
      count(*)::int as days,
      count(*) filter (where r.qty > 0)::int as active_days,
      count(*) filter (where r.qty = 0)::int as zero_days,
      (select rr.data from r rr order by rr.qty asc,  rr.data asc  limit 1) as min_day,
      (select rr.qty  from r rr order by rr.qty asc,  rr.data asc  limit 1) as min_qty,
      (select rr.data from r rr order by rr.qty desc, rr.data asc  limit 1) as max_day,
      (select rr.qty  from r rr order by rr.qty desc, rr.data asc  limit 1) as max_qty
    from r;
    return;
  end if;

  -- FAMIGLIA
  if v_type = 'famiglia' then
    return query
    with r as (
      select
        data::date as data,
        qty_venduta_tot::numeric as qty,
        imponibile_netto_tot::numeric as imp
      from public.core_analytics__series_daily_famiglia_lc
      where entity_key_lc = v_key
        and data between p_date_from and p_date_to
    )
    select
      coalesce(sum(r.qty),0) as qty_tot,
      coalesce(sum(r.imp),0) as imp_tot,
      count(*)::int as days,
      count(*) filter (where r.qty > 0)::int as active_days,
      count(*) filter (where r.qty = 0)::int as zero_days,
      (select rr.data from r rr order by rr.qty asc,  rr.data asc  limit 1) as min_day,
      (select rr.qty  from r rr order by rr.qty asc,  rr.data asc  limit 1) as min_qty,
      (select rr.data from r rr order by rr.qty desc, rr.data asc  limit 1) as max_day,
      (select rr.qty  from r rr order by rr.qty desc, rr.data asc  limit 1) as max_qty
    from r;
    return;
  end if;

  -- CATEGORIA
  if v_type = 'categoria' then
    return query
    with r as (
      select
        data::date as data,
        qty_venduta_tot::numeric as qty,
        imponibile_netto_tot::numeric as imp
      from public.core_analytics__series_daily_categoria_lc
      where entity_key_lc = v_key
        and data between p_date_from and p_date_to
    )
    select
      coalesce(sum(r.qty),0) as qty_tot,
      coalesce(sum(r.imp),0) as imp_tot,
      count(*)::int as days,
      count(*) filter (where r.qty > 0)::int as active_days,
      count(*) filter (where r.qty = 0)::int as zero_days,
      (select rr.data from r rr order by rr.qty asc,  rr.data asc  limit 1) as min_day,
      (select rr.qty  from r rr order by rr.qty asc,  rr.data asc  limit 1) as min_qty,
      (select rr.data from r rr order by rr.qty desc, rr.data asc  limit 1) as max_day,
      (select rr.qty  from r rr order by rr.qty desc, rr.data asc  limit 1) as max_qty
    from r;
    return;
  end if;

  -- FASCIA
  if v_type = 'fascia' then
    return query
    with r as (
      select
        data::date as data,
        qty_venduta_tot::numeric as qty,
        imponibile_netto_tot::numeric as imp
      from public.core_analytics__series_daily_fascia_lc
      where entity_key_lc = v_key
        and data between p_date_from and p_date_to
    )
    select
      coalesce(sum(r.qty),0) as qty_tot,
      coalesce(sum(r.imp),0) as imp_tot,
      count(*)::int as days,
      count(*) filter (where r.qty > 0)::int as active_days,
      count(*) filter (where r.qty = 0)::int as zero_days,
      (select rr.data from r rr order by rr.qty asc,  rr.data asc  limit 1) as min_day,
      (select rr.qty  from r rr order by rr.qty asc,  rr.data asc  limit 1) as min_qty,
      (select rr.data from r rr order by rr.qty desc, rr.data asc  limit 1) as max_day,
      (select rr.qty  from r rr order by rr.qty desc, rr.data asc  limit 1) as max_qty
    from r;
    return;
  end if;

  -- FASCIA PREZZO
  if v_type = 'fascia_prezzo' then
    return query
    with r as (
      select
        data::date as data,
        qty_venduta_tot::numeric as qty,
        imponibile_netto_tot::numeric as imp
      from public.core_analytics__series_daily_fascia_prezzo_lc
      where entity_key_lc = v_key
        and data between p_date_from and p_date_to
    )
    select
      coalesce(sum(r.qty),0) as qty_tot,
      coalesce(sum(r.imp),0) as imp_tot,
      count(*)::int as days,
      count(*) filter (where r.qty > 0)::int as active_days,
      count(*) filter (where r.qty = 0)::int as zero_days,
      (select rr.data from r rr order by rr.qty asc,  rr.data asc  limit 1) as min_day,
      (select rr.qty  from r rr order by rr.qty asc,  rr.data asc  limit 1) as min_qty,
      (select rr.data from r rr order by rr.qty desc, rr.data asc  limit 1) as max_day,
      (select rr.qty  from r rr order by rr.qty desc, rr.data asc  limit 1) as max_qty
    from r;
    return;
  end if;

  raise exception 'Unsupported p_entity_type=% (normalized=%)', p_entity_type, v_type;
end;
$$;


-- ============================================================
-- SECTION 10: FUNCTION — core_analytics__stock_and_reorder_v1
-- Returns stock quantity (from latest upload) and reorder quantity
-- (from order suggestions) for a given entity.
-- Returns {stock_qty: null, reorder_qty: 0} when tables are empty.
-- Extracted VERBATIM from sql/schema/current-schema.sql.
-- ============================================================

CREATE OR REPLACE FUNCTION public.core_analytics__stock_and_reorder_v1(
    p_entity_type  text,
    p_entity_key   text,
    p_fascia_prezzo text DEFAULT NULL
)
RETURNS TABLE(
    stock_qty   numeric,
    reorder_qty numeric
)
LANGUAGE plpgsql STABLE
AS $$
declare
  v_entity_type text := lower(trim(coalesce(p_entity_type,'')));
  v_key         text := lower(trim(coalesce(p_entity_key,'')));
  v_fp          text := nullif(lower(trim(coalesce(p_fascia_prezzo,''))), '');
  v_latest_date date;
begin
  if v_entity_type = '' or v_key = '' then
    stock_qty   := null;
    reorder_qty := null;
    return next;
    return;
  end if;

  -- 1) latest stock date
  select max(data_rilevazione)::date
    into v_latest_date
    from public.greenhouse_stock_raw_upload;

  -- se non ho stock date, stock null (ma reorder lo posso calcolare)
  -- 2) STOCK: greenhouse_stock_enriched filtrata su ultima data
  if v_latest_date is null then
    stock_qty := null;
  else
    select coalesce(sum(se.qty_giacenza), 0)
      into stock_qty
      from public.greenhouse_stock_enriched se
     where se.data_rilevazione::date = v_latest_date
       and (
           (v_entity_type = 'famiglia'      and lower(trim(se.famiglia))              = v_key)
        or (v_entity_type = 'categoria'     and lower(trim(se.categoria_corretta))    = v_key)
        or (v_entity_type = 'fascia'        and lower(trim(se.fascia_corretta))       = v_key)
        or (v_entity_type = 'fascia_prezzo' and lower(trim(se.fascia_prezzo_iva_inc)) = v_key)
        or (v_entity_type = 'articolo'      and lower(trim(se.codart))               = v_key)
       )
       and (
           v_fp is null
        or v_entity_type not in ('famiglia','categoria','fascia')
        or lower(trim(se.fascia_prezzo_iva_inc)) = v_fp
       );
  end if;

  -- 3) REORDER: dalla view greenhouse_order_suggestions_enriched_v2 (già qty_da_ordinare >= 1)
  -- articolo non supportato in reorder (come già fai)
  if v_entity_type = 'articolo' then
    reorder_qty := null;
  else
    select coalesce(sum(v.qty_da_ordinare), 0)
      into reorder_qty
      from public.greenhouse_order_suggestions_enriched_v2 v
     where (
           (v_entity_type = 'famiglia'      and lower(trim(v.famiglia))              = v_key)
        or (v_entity_type = 'categoria'     and lower(trim(v.categoria_corretta))    = v_key)
        or (v_entity_type = 'fascia'        and lower(trim(v.fascia_corretta))       = v_key)
        or (v_entity_type = 'fascia_prezzo' and lower(trim(v.fascia_prezzo_iva_inc)) = v_key)
       )
       and (
           v_fp is null
        or v_entity_type not in ('famiglia','categoria','fascia')
        or lower(trim(v.fascia_prezzo_iva_inc)) = v_fp
       );
  end if;

  return next;
end;
$$;


-- ============================================================
-- END OF WAVE 7B.2-B SCHEMA
-- Object counts:
--   Tables:    2  (greenhouse_stock_raw_upload, greenhouse_sales_family_daily_fact)
--   Views:     6  (stock_enriched, forecast_windows, stock_family_latest,
--                  sales_family_meta, order_suggestions_v2, order_suggestions_enriched_v2)
--   Functions: 2  (core_analytics__range_totals_v2, core_analytics__stock_and_reorder_v1)
--   Total:    10
-- ============================================================
