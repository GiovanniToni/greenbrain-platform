--
-- PostgreSQL database dump
--

\restrict 6gkfZkb2BfWJ8zQOgMQKszzrTgr6jZD31VarZC8wdFW4BVgYYvApyknrPhgWR5x

-- Dumped from database version 16.13
-- Dumped by pg_dump version 16.13

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: ml_ops; Type: SCHEMA; Schema: -; Owner: greenbrain_cliente_reale_demo
--

CREATE SCHEMA ml_ops;


ALTER SCHEMA ml_ops OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: core_analytics__catalog_children(text, text, text, text, text, integer); Type: FUNCTION; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE FUNCTION public.core_analytics__catalog_children(p_level text, p_fascia text DEFAULT NULL::text, p_categoria text DEFAULT NULL::text, p_famiglia text DEFAULT NULL::text, p_fascia_prezzo text DEFAULT NULL::text, p_limit integer DEFAULT 500) RETURNS TABLE(node_type text, node_key text, label text, extra jsonb)
    LANGUAGE sql STABLE
    AS $$
with base as (
  select *
  from public.core_analytics__components_articles a
  where (p_fascia is null or lower(a.fascia_corretta) = lower(p_fascia))
    and (p_categoria is null or lower(a.categoria_corretta) = lower(p_categoria))
    and (p_famiglia is null or lower(a.famiglia) = lower(p_famiglia))
    and (p_fascia_prezzo is null or lower(a.fascia_prezzo_iva_inc) = lower(p_fascia_prezzo))
)

-- ROOT: fasce
select
  'fascia'::text as node_type,
  coalesce(fascia_corretta, '(senza fascia)') as node_key,
  coalesce(fascia_corretta, '(senza fascia)') as label,
  jsonb_build_object('count', count(*)) as extra
from base
where lower(p_level) = 'fascia'
group by 1,2,3

union all

-- categorie (dato fascia)
select
  'categoria'::text,
  coalesce(categoria_corretta, '(senza categoria)'),
  coalesce(categoria_corretta, '(senza categoria)'),
  jsonb_build_object('count', count(*)) as extra
from base
where lower(p_level) = 'categoria'
group by 1,2,3

union all

-- famiglie (dato fascia+categoria)
select
  'famiglia'::text,
  coalesce(famiglia, '(senza famiglia)'),
  coalesce(famiglia, '(senza famiglia)'),
  jsonb_build_object('count', count(*)) as extra
from base
where lower(p_level) = 'famiglia'
group by 1,2,3

union all

-- fasce prezzo (dato fascia+categoria+famiglia)
select
  'fascia_prezzo'::text,
  coalesce(fascia_prezzo_iva_inc, '(senza fascia prezzo)'),
  coalesce(fascia_prezzo_iva_inc, '(senza fascia prezzo)'),
  jsonb_build_object('count', count(*)) as extra
from base
where lower(p_level) = 'fascia_prezzo'
group by 1,2,3

union all

-- articoli (dato fascia+categoria+famiglia+fascia_prezzo)
select
  'articolo'::text,
  codart as node_key,
  (codart || ' — ' || articolo_nome)::text as label,
  jsonb_build_object(
    'codart', codart,
    'articolo_nome', articolo_nome,
    'pot_size', pot_size,
    'prezzo_iva_inclusa', prezzo_iva_inclusa
  ) as extra
from base
where lower(p_level) = 'articolo'
  and codart is not null
limit greatest(coalesce(p_limit, 500), 0);
$$;


ALTER FUNCTION public.core_analytics__catalog_children(p_level text, p_fascia text, p_categoria text, p_famiglia text, p_fascia_prezzo text, p_limit integer) OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__entity_hierarchy_tree_v1(text, text, date, date, integer, text, text, text, text); Type: FUNCTION; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE FUNCTION public.core_analytics__entity_hierarchy_tree_v1(p_entity_type text, p_entity_key text, p_date_from date, p_date_to date, p_top_n integer, p_fascia text DEFAULT NULL::text, p_categoria text DEFAULT NULL::text, p_famiglia text DEFAULT NULL::text, p_fascia_prezzo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE sql
    AS $$with params as (
  select
    lower(trim(coalesce(p_entity_type,''))) as et,
    lower(trim(coalesce(p_entity_key,'')))  as ek,
    nullif(greatest(coalesce(p_top_n, 0), 0), 0) as top_n
),
ctx as (
  select
    nullif(lower(trim(coalesce(p_fascia,''))), '')        as c_fascia,
    nullif(lower(trim(coalesce(p_categoria,''))), '')     as c_categoria,
    nullif(lower(trim(coalesce(p_famiglia,''))), '')      as c_famiglia,
    nullif(lower(trim(coalesce(p_fascia_prezzo,''))), '') as c_fp
),

base as (
  select
    coalesce(a.fascia_corretta, '(senza fascia)')              as fascia_key,
    coalesce(a.categoria_corretta, '(senza categoria)')        as categoria_key,
    coalesce(a.famiglia, '(senza famiglia)')                   as famiglia_key,
    coalesce(a.fascia_prezzo_iva_inc, '(senza fascia prezzo)') as fp_key,
    a.codart,
    a.articolo_nome,
    a.pot_size,
    a.prezzo_iva_inclusa
  from public.core_analytics__components_articles a
  cross join params p
  cross join ctx c
  where
    (
      (p.et = 'famiglia'      and lower(coalesce(a.famiglia,'(senza famiglia)')) = p.ek) or
      (p.et = 'categoria'     and lower(coalesce(a.categoria_corretta,'(senza categoria)')) = p.ek) or
      (p.et = 'fascia'        and lower(coalesce(a.fascia_corretta,'(senza fascia)')) = p.ek) or
      (p.et = 'fascia_prezzo' and lower(coalesce(a.fascia_prezzo_iva_inc,'(senza fascia prezzo)')) = p.ek) or
      (p.et = 'articolo'      and a.codart = btrim(coalesce(p_entity_key,'')))
    )
    and (c.c_fascia    is null or lower(coalesce(a.fascia_corretta,'(senza fascia)')) = c.c_fascia)
    and (c.c_categoria is null or lower(coalesce(a.categoria_corretta,'(senza categoria)')) = c.c_categoria)
    and (c.c_famiglia  is null or lower(coalesce(a.famiglia,'(senza famiglia)')) = c.c_famiglia)
    and (c.c_fp        is null or lower(coalesce(a.fascia_prezzo_iva_inc,'(senza fascia prezzo)')) = c.c_fp)
),

articles_ranked as (
  select
    b.fascia_key, b.categoria_key, b.famiglia_key, b.fp_key,
    b.codart, b.articolo_nome, b.pot_size, b.prezzo_iva_inclusa,
    row_number() over (
      partition by b.fascia_key, b.categoria_key, b.famiglia_key, b.fp_key
      order by
        case when b.pot_size is null or btrim(b.pot_size) = '' then 1 else 0 end,
        nullif(regexp_replace(b.pot_size, '[^0-9\.]', '', 'g'), '')::numeric nulls last,
        case when b.pot_size is null or btrim(b.pot_size) = '' then b.prezzo_iva_inclusa else null end nulls last,
        b.codart asc
    ) as rn
  from base b
),
articles_trim as (
  select * from articles_ranked where rn <= 300
),
articles_json as (
  select
    ar.fascia_key, ar.categoria_key, ar.famiglia_key, ar.fp_key,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'entity_type','articolo',
          'entity_key', ar.codart,
          'label', ar.codart || ' — ' || ar.articolo_nome,
          'qty_tot', 0,
          'imponibile_tot', 0,
          'num_articoli_tot', null,
          'extra', jsonb_build_object(
            'pot_size', ar.pot_size,
            'prezzo_iva_inclusa', ar.prezzo_iva_inclusa
          )
        )
        order by ar.rn
      ),
      '[]'::jsonb
    ) as children_articoli
  from articles_trim ar
  group by 1,2,3,4
),

fp_groups as (
  select distinct fascia_key, categoria_key, famiglia_key, fp_key
  from base
),
fp_ranked as (
  select
    g.*,
    row_number() over (
      partition by g.fascia_key, g.categoria_key, g.famiglia_key
      order by g.fp_key asc
    ) as rn
  from fp_groups g
),
fp_trim as (
  select r.*
  from fp_ranked r
  cross join params p
  where p.top_n is null or r.rn <= p.top_n
),
fp_json_per_family as (
  select
    fpt.fascia_key, fpt.categoria_key, fpt.famiglia_key,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'entity_type', 'fascia_prezzo',
          'entity_key', fpt.fp_key,
          'label', fpt.fp_key,
          'qty_tot', 0,
          'imponibile_tot', 0,
          'num_articoli_tot', null,
          'children', coalesce(aj.children_articoli, '[]'::jsonb)
        )
        order by fpt.fp_key asc
      ),
      '[]'::jsonb
    ) as children_fp
  from fp_trim fpt
  left join articles_json aj
    on aj.fascia_key = fpt.fascia_key
   and aj.categoria_key = fpt.categoria_key
   and aj.famiglia_key = fpt.famiglia_key
   and aj.fp_key = fpt.fp_key
  group by 1,2,3
),

fam_groups as (
  select distinct fascia_key, categoria_key, famiglia_key
  from base
),
fam_ranked as (
  select
    g.*,
    row_number() over (
      partition by g.fascia_key, g.categoria_key
      order by g.famiglia_key asc
    ) as rn
  from fam_groups g
),
fam_trim as (
  select r.*
  from fam_ranked r
  cross join params p
  where p.top_n is null or r.rn <= p.top_n
),
fam_json_per_cat as (
  select
    ft.fascia_key, ft.categoria_key,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'entity_type', 'famiglia',
          'entity_key', ft.famiglia_key,
          'label', ft.famiglia_key,
          'qty_tot', 0,
          'imponibile_tot', 0,
          'num_articoli_tot', null,
          'children', coalesce(fp.children_fp, '[]'::jsonb)
        )
        order by ft.famiglia_key asc
      ),
      '[]'::jsonb
    ) as children_famiglie
  from fam_trim ft
  left join fp_json_per_family fp
    on fp.fascia_key = ft.fascia_key
   and fp.categoria_key = ft.categoria_key
   and fp.famiglia_key = ft.famiglia_key
  group by 1,2
),

cat_groups as (
  select distinct fascia_key, categoria_key
  from base
),
cat_ranked as (
  select
    g.*,
    row_number() over (
      partition by g.fascia_key
      order by g.categoria_key asc
    ) as rn
  from cat_groups g
),
cat_trim as (
  select r.*
  from cat_ranked r
  cross join params p
  where p.top_n is null or r.rn <= p.top_n
),
cat_json_per_fascia as (
  select
    ct.fascia_key,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'entity_type', 'categoria',
          'entity_key', ct.categoria_key,
          'label', ct.categoria_key,
          'qty_tot', 0,
          'imponibile_tot', 0,
          'num_articoli_tot', null,
          'children', coalesce(fj.children_famiglie, '[]'::jsonb)
        )
        order by ct.categoria_key asc
      ),
      '[]'::jsonb
    ) as children_categorie
  from cat_trim ct
  left join fam_json_per_cat fj
    on fj.fascia_key = ct.fascia_key
   and fj.categoria_key = ct.categoria_key
  group by 1
),

fas_groups as (
  select distinct fascia_key
  from base
),
fas_ranked as (
  select
    g.*,
    row_number() over (order by g.fascia_key asc) as rn
  from fas_groups g
),
fas_trim as (
  select r.*
  from fas_ranked r
  cross join params p
  where p.top_n is null or r.rn <= p.top_n
),
fas_json as (
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'entity_type', 'fascia',
          'entity_key', ft.fascia_key,
          'label', ft.fascia_key,
          'qty_tot', 0,
          'imponibile_tot', 0,
          'num_articoli_tot', null,
          'children', coalesce(cj.children_categorie, '[]'::jsonb)
        )
        order by ft.fascia_key asc
      ),
      '[]'::jsonb
    ) as tree
  from fas_trim ft
  left join cat_json_per_fascia cj
    on cj.fascia_key = ft.fascia_key
)

select jsonb_build_object(
  'entity_type', (select et from params),
  'entity_key',  p_entity_key,
  'date_from',   p_date_from,
  'date_to',     p_date_to,
  'totals',      jsonb_build_object('qty_tot',0,'imponibile_tot',0,'num_articoli_tot',0),
  'tree',        (select tree from fas_json)
);$$;


ALTER FUNCTION public.core_analytics__entity_hierarchy_tree_v1(p_entity_type text, p_entity_key text, p_date_from date, p_date_to date, p_top_n integer, p_fascia text, p_categoria text, p_famiglia text, p_fascia_prezzo text) OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__future_window_stats_v2(text, text, date, integer[]); Type: FUNCTION; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE FUNCTION public.core_analytics__future_window_stats_v2(p_entity_type text, p_entity_key text, p_anchor_to date DEFAULT CURRENT_DATE, p_windows integer[] DEFAULT ARRAY[7, 14, 30, 60]) RETURNS TABLE(window_days integer, min_qty numeric, max_qty numeric, avg_qty numeric)
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


ALTER FUNCTION public.core_analytics__future_window_stats_v2(p_entity_type text, p_entity_key text, p_anchor_to date, p_windows integer[]) OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__list_catalog(text, integer); Type: FUNCTION; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE FUNCTION public.core_analytics__list_catalog(p_entity_type text, p_limit integer DEFAULT 500) RETURNS TABLE(entity_type text, entity_key text, label text)
    LANGUAGE sql STABLE
    AS $$
  select
    c.entity_type,
    c.entity_key,
    c.label
  from public.core_analytics__catalog c
  where c.entity_type = p_entity_type
  order by c.label asc
  limit greatest(1, least(p_limit, 2000));
$$;


ALTER FUNCTION public.core_analytics__list_catalog(p_entity_type text, p_limit integer) OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__range_totals_v2(text, text, date, date); Type: FUNCTION; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE FUNCTION public.core_analytics__range_totals_v2(p_entity_type text, p_entity_key text, p_date_from date, p_date_to date) RETURNS TABLE(qty_tot numeric, imp_tot numeric, days integer, active_days integer, zero_days integer, min_day date, min_qty numeric, max_day date, max_qty numeric)
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


ALTER FUNCTION public.core_analytics__range_totals_v2(p_entity_type text, p_entity_key text, p_date_from date, p_date_to date) OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__search_catalog_rich(text, integer); Type: FUNCTION; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE FUNCTION public.core_analytics__search_catalog_rich(term text, limit_n integer DEFAULT 50) RETURNS TABLE(entity_type text, entity_key text, label text, score real, fascia text, categoria text, famiglia text, fascia_prezzo text, codart text, articolo_nome text, pot_size text, prezzo_iva_inclusa numeric)
    LANGUAGE sql STABLE
    AS $$
with params as (
  select
    lower(trim(term)) as t,
    greatest(coalesce(limit_n, 50), 1) as lim
),

-- ======================================================
-- ENTITÀ (fascia / categoria / famiglia / fascia_prezzo)
-- pesca dalla MV indicizzata
-- ======================================================
base_entities as (
  select
    e.entity_type::text as entity_type,
    e.entity_key::text  as entity_key,
    e.label::text       as label,
    similarity(lower(e.label), p.t)::real as score,
    e.fascia::text        as fascia,
    e.categoria::text     as categoria,
    e.famiglia::text      as famiglia,
    e.fascia_prezzo::text as fascia_prezzo,
    null::text    as codart,
    null::text    as articolo_nome,
    null::text    as pot_size,
    null::numeric as prezzo_iva_inclusa
  from public.mv_core_analytics__catalog_entities e
  cross join params p
  where e.label is not null
    and (
      lower(e.label) % p.t
      or lower(e.label) like '%' || p.t || '%'
    )
),

-- =========================
-- ARTICOLI
-- =========================
base_articles as (
  select
    'articolo'::text as entity_type,
    a.codart as entity_key,
    (a.codart || ' — ' || coalesce(a.articolo_nome,'(senza descrizione)')) as label,
    greatest(
      similarity(lower(a.codart), p.t),
      similarity(lower(coalesce(a.articolo_nome,'')), p.t)
    )::real as score,
    a.fascia_corretta        as fascia,
    a.categoria_corretta     as categoria,
    a.famiglia               as famiglia,
    a.fascia_prezzo_iva_inc  as fascia_prezzo,
    a.codart,
    a.articolo_nome,
    a.pot_size,
    a.prezzo_iva_inclusa
  from public.core_analytics__components_articles a
  cross join params p
  where a.codart is not null
    and (
      lower(a.codart) % p.t
      or lower(a.codart) like '%' || p.t || '%'
      or lower(coalesce(a.articolo_nome,'')) % p.t
      or lower(coalesce(a.articolo_nome,'')) like '%' || p.t || '%'
    )
),

-- =========================
-- UNION + RANK
-- =========================
all_hits as (
  select * from base_entities
  union all
  select * from base_articles
),

ranked as (
  select
    *,
    row_number() over (order by score desc, label asc) as rn
  from all_hits
)

select
  entity_type,
  entity_key,
  label,
  score,
  fascia,
  categoria,
  famiglia,
  fascia_prezzo,
  codart,
  articolo_nome,
  pot_size,
  prezzo_iva_inclusa
from ranked, params p
where rn <= p.lim
order by score desc, label asc;
$$;


ALTER FUNCTION public.core_analytics__search_catalog_rich(term text, limit_n integer) OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__stock_and_reorder_v1(text, text, text); Type: FUNCTION; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE FUNCTION public.core_analytics__stock_and_reorder_v1(p_entity_type text, p_entity_key text, p_fascia_prezzo text DEFAULT NULL::text) RETURNS TABLE(stock_qty numeric, reorder_qty numeric)
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


ALTER FUNCTION public.core_analytics__stock_and_reorder_v1(p_entity_type text, p_entity_key text, p_fascia_prezzo text) OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_planner__get_current_week52(); Type: FUNCTION; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE FUNCTION public.core_planner__get_current_week52() RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT jsonb_build_object(
    'today', CURRENT_DATE,
    'week_52', EXTRACT(WEEK FROM CURRENT_DATE)::int,
    'iso_year', EXTRACT(ISOYEAR FROM CURRENT_DATE)::int,
    'week_start', date_trunc('week', CURRENT_DATE)::date
);
$$;


ALTER FUNCTION public.core_planner__get_current_week52() OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: dashboard__kpis_v2(); Type: FUNCTION; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE FUNCTION public.dashboard__kpis_v2() RETURNS TABLE(sales_week numeric, sales_trend numeric, stock_out_risk bigint, products_monitored bigint, forecast_14d numeric, reorder_lines bigint, reorder_risk_lines bigint, reorder_qty_tot numeric, sales_ytd numeric, sales_ytd_trend numeric)
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


ALTER FUNCTION public.dashboard__kpis_v2() OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: gb_touch_updated_at(); Type: FUNCTION; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE FUNCTION public.gb_touch_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.gb_touch_updated_at() OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: refresh_dense_range_from_fact(date, date); Type: FUNCTION; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE FUNCTION public.refresh_dense_range_from_fact(p_start date, p_end date) RETURNS void
    LANGUAGE sql
    AS $$
  INSERT INTO public.greenhouse_sales_family_daily_dense (
    data, famiglia, fascia_prezzo_iva_inc,
    qty_venduta, imponibile_netto_tot, num_articoli,
    fascia_corretta, categoria_corretta,
    pot_sizes_text, pot_sizes_json,
    articoli_inclusi, articoli_json
  )
  SELECT
    c.data,
    s.famiglia,
    s.fascia_prezzo_iva_inc,
    COALESCE(f.qty_venduta, 0),
    COALESCE(f.imponibile_netto_tot, 0),
    COALESCE(f.num_articoli, 0),
    s.fascia_corretta,
    s.categoria_corretta,
    COALESCE(f.pot_sizes_text, ''),
    COALESCE(f.pot_sizes_json, '[]'::jsonb),
    f.articoli_inclusi,
    COALESCE(f.articoli_json, '[]'::jsonb)
  FROM (
    SELECT gs::date AS data
    FROM generate_series(p_start, p_end, interval '1 day') gs
  ) c
  CROSS JOIN public.greenhouse_series_list_fact s
  LEFT JOIN public.greenhouse_sales_family_daily_fact f
    ON f.data = c.data
   AND f.famiglia = s.famiglia
   AND f.fascia_prezzo_iva_inc = s.fascia_prezzo_iva_inc
  ON CONFLICT (data, famiglia, fascia_prezzo_iva_inc)
  DO UPDATE SET
    qty_venduta = EXCLUDED.qty_venduta,
    imponibile_netto_tot = EXCLUDED.imponibile_netto_tot,
    num_articoli = EXCLUDED.num_articoli,
    fascia_corretta = EXCLUDED.fascia_corretta,
    categoria_corretta = EXCLUDED.categoria_corretta,
    pot_sizes_text = EXCLUDED.pot_sizes_text,
    pot_sizes_json = EXCLUDED.pot_sizes_json,
    articoli_inclusi = EXCLUDED.articoli_inclusi,
    articoli_json = EXCLUDED.articoli_json;
$$;


ALTER FUNCTION public.refresh_dense_range_from_fact(p_start date, p_end date) OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: refresh_forecast_features_dense_range(date, date); Type: FUNCTION; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE FUNCTION public.refresh_forecast_features_dense_range(p_start date, p_end date) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_lb date;
BEGIN
  IF p_start IS NULL OR p_end IS NULL OR p_start > p_end THEN
    RAISE EXCEPTION 'range non valido: % - %', p_start, p_end;
  END IF;

  v_lb := (p_start - INTERVAL '28 days')::date;

  PERFORM set_config('statement_timeout', '600000', true);

  INSERT INTO public.greenhouse_forecast_features_dense (
    data, famiglia, fascia_prezzo_iva_inc,
    qty_venduta, imponibile_netto_tot, num_articoli,
    fascia_corretta, categoria_corretta,
    pot_sizes_text, pot_sizes_json,
    articoli_inclusi, articoli_json,
    tmin_c, tmax_c, tavg_c, rain_mm, sun_hours,
    is_holiday, holiday_name,
    dow, week_num, month_num, year_num,
    qty_lag_1, qty_lag_2, qty_lag_3, qty_lag_7, qty_lag_10, qty_lag_14,
    qty_ma_3, qty_ma_7, qty_ma_10, qty_ma_14, qty_ma_28,
    created_at, updated_at
  )
  WITH base AS (
    SELECT
      d.data, d.famiglia, d.fascia_prezzo_iva_inc,
      d.qty_venduta, d.imponibile_netto_tot, d.num_articoli,
      d.fascia_corretta, d.categoria_corretta,
      d.pot_sizes_text, d.pot_sizes_json,
      d.articoli_inclusi, d.articoli_json
    FROM public.greenhouse_sales_family_daily_dense d
    WHERE d.data BETWEEN v_lb AND p_end
  ),
  feat AS (
    SELECT
      b.*,
      w.tmin_c, w.tmax_c, w.tavg_c, w.rain_mm, w.sun_hours,
      COALESCE(h.is_holiday, false) AS is_holiday,
      h.holiday_name,
      EXTRACT(dow   FROM b.data)::int AS dow,
      EXTRACT(week  FROM b.data)::int AS week_num,
      EXTRACT(month FROM b.data)::int AS month_num,
      EXTRACT(year  FROM b.data)::int AS year_num,
      lag(b.qty_venduta, 1)  OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data) AS qty_lag_1,
      lag(b.qty_venduta, 2)  OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data) AS qty_lag_2,
      lag(b.qty_venduta, 3)  OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data) AS qty_lag_3,
      lag(b.qty_venduta, 7)  OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data) AS qty_lag_7,
      lag(b.qty_venduta, 10) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data) AS qty_lag_10,
      lag(b.qty_venduta, 14) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data) AS qty_lag_14,
      avg(b.qty_venduta) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING)  AS qty_ma_3,
      avg(b.qty_venduta) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING)  AS qty_ma_7,
      avg(b.qty_venduta) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data ROWS BETWEEN 10 PRECEDING AND 1 PRECEDING) AS qty_ma_10,
      avg(b.qty_venduta) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING) AS qty_ma_14,
      avg(b.qty_venduta) OVER (PARTITION BY b.famiglia, b.fascia_prezzo_iva_inc ORDER BY b.data ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING) AS qty_ma_28
    FROM base b
    LEFT JOIN public.greenhouse_weather_daily w ON w.data = b.data
    LEFT JOIN public.greenhouse_holidays h ON h.data = b.data
  )
  SELECT
    data, famiglia, fascia_prezzo_iva_inc,
    qty_venduta, imponibile_netto_tot, num_articoli,
    fascia_corretta, categoria_corretta,
    pot_sizes_text, pot_sizes_json,
    articoli_inclusi, articoli_json,
    tmin_c, tmax_c, tavg_c, rain_mm, sun_hours,
    is_holiday, holiday_name,
    dow, week_num, month_num, year_num,
    qty_lag_1, qty_lag_2, qty_lag_3, qty_lag_7, qty_lag_10, qty_lag_14,
    qty_ma_3, qty_ma_7, qty_ma_10, qty_ma_14, qty_ma_28,
    now(), now()
  FROM feat
  WHERE data BETWEEN p_start AND p_end
  ON CONFLICT (data, famiglia, fascia_prezzo_iva_inc)
  DO UPDATE SET
    qty_venduta = EXCLUDED.qty_venduta,
    imponibile_netto_tot = EXCLUDED.imponibile_netto_tot,
    num_articoli = EXCLUDED.num_articoli,
    fascia_corretta = EXCLUDED.fascia_corretta,
    categoria_corretta = EXCLUDED.categoria_corretta,
    pot_sizes_text = EXCLUDED.pot_sizes_text,
    pot_sizes_json = EXCLUDED.pot_sizes_json,
    articoli_inclusi = EXCLUDED.articoli_inclusi,
    articoli_json = EXCLUDED.articoli_json,
    tmin_c = EXCLUDED.tmin_c,
    tmax_c = EXCLUDED.tmax_c,
    tavg_c = EXCLUDED.tavg_c,
    rain_mm = EXCLUDED.rain_mm,
    sun_hours = EXCLUDED.sun_hours,
    is_holiday = EXCLUDED.is_holiday,
    holiday_name = EXCLUDED.holiday_name,
    dow = EXCLUDED.dow,
    week_num = EXCLUDED.week_num,
    month_num = EXCLUDED.month_num,
    year_num = EXCLUDED.year_num,
    qty_lag_1 = EXCLUDED.qty_lag_1,
    qty_lag_2 = EXCLUDED.qty_lag_2,
    qty_lag_3 = EXCLUDED.qty_lag_3,
    qty_lag_7 = EXCLUDED.qty_lag_7,
    qty_lag_10 = EXCLUDED.qty_lag_10,
    qty_lag_14 = EXCLUDED.qty_lag_14,
    qty_ma_3 = EXCLUDED.qty_ma_3,
    qty_ma_7 = EXCLUDED.qty_ma_7,
    qty_ma_10 = EXCLUDED.qty_ma_10,
    qty_ma_14 = EXCLUDED.qty_ma_14,
    qty_ma_28 = EXCLUDED.qty_ma_28,
    updated_at = now();
END;
$$;


ALTER FUNCTION public.refresh_forecast_features_dense_range(p_start date, p_end date) OWNER TO greenbrain_cliente_reale_demo;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: family_run_log_v1; Type: TABLE; Schema: ml_ops; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE ml_ops.family_run_log_v1 (
    family_run_id text NOT NULL,
    pipeline_run_id text,
    job_type text,
    family_name text,
    demand_class_final text,
    model_code text,
    started_at timestamp with time zone,
    finished_at timestamp with time zone,
    status text,
    rows_written integer,
    artifact_path text,
    error_message text,
    error_trace text
);


ALTER TABLE ml_ops.family_run_log_v1 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: pipeline_run_log_v1; Type: TABLE; Schema: ml_ops; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE ml_ops.pipeline_run_log_v1 (
    run_id text NOT NULL,
    job_type text,
    trigger_mode text,
    status text,
    started_at timestamp with time zone,
    finished_at timestamp with time zone,
    duration_min numeric(8,2),
    host_name text,
    rows_processed integer,
    error_message text,
    git_sha text,
    notes text
);


ALTER TABLE ml_ops.pipeline_run_log_v1 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: v_daily_pipeline_summary_v1; Type: VIEW; Schema: ml_ops; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW ml_ops.v_daily_pipeline_summary_v1 AS
 SELECT (started_at)::date AS day,
    job_type,
    count(*) AS runs,
    count(*) FILTER (WHERE (status = 'ok'::text)) AS ok_runs,
    count(*) FILTER (WHERE (status <> 'ok'::text)) AS bad_runs
   FROM ml_ops.pipeline_run_log_v1
  GROUP BY ((started_at)::date), job_type;


ALTER VIEW ml_ops.v_daily_pipeline_summary_v1 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: v_pipeline_runs_recent_v1; Type: VIEW; Schema: ml_ops; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW ml_ops.v_pipeline_runs_recent_v1 AS
 SELECT run_id,
    job_type,
    trigger_mode,
    status,
    started_at,
    finished_at,
    duration_min,
    host_name,
    rows_processed,
    error_message,
    git_sha,
    notes
   FROM ml_ops.pipeline_run_log_v1
  ORDER BY started_at DESC;


ALTER VIEW ml_ops.v_pipeline_runs_recent_v1 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: _runtime_bootstrap; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public._runtime_bootstrap (
    id integer NOT NULL,
    wave text NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL,
    note text
);


ALTER TABLE public._runtime_bootstrap OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: _runtime_bootstrap_id_seq; Type: SEQUENCE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE SEQUENCE public._runtime_bootstrap_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public._runtime_bootstrap_id_seq OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: _runtime_bootstrap_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER SEQUENCE public._runtime_bootstrap_id_seq OWNED BY public._runtime_bootstrap.id;


--
-- Name: calendar_events; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.calendar_events (
    id integer NOT NULL,
    date date NOT NULL,
    name text NOT NULL,
    impact_level text
);


ALTER TABLE public.calendar_events OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: calendar_events_id_seq; Type: SEQUENCE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE SEQUENCE public.calendar_events_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.calendar_events_id_seq OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: calendar_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER SEQUENCE public.calendar_events_id_seq OWNED BY public.calendar_events.id;


--
-- Name: t_core_analytics__breakdown_daily_categoria_fp_v2; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__breakdown_daily_categoria_fp_v2 (
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


ALTER TABLE public.t_core_analytics__breakdown_daily_categoria_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__breakdown_daily_categoria_fp_v2; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__breakdown_daily_categoria_fp_v2 AS
 SELECT data,
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


ALTER VIEW public.core_analytics__breakdown_daily_categoria_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__breakdown_daily_famiglia_fp_v2; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__breakdown_daily_famiglia_fp_v2 (
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


ALTER TABLE public.t_core_analytics__breakdown_daily_famiglia_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__breakdown_daily_famiglia_fp_v2; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__breakdown_daily_famiglia_fp_v2 AS
 SELECT data,
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


ALTER VIEW public.core_analytics__breakdown_daily_famiglia_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__breakdown_daily_fascia_fp_v2; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__breakdown_daily_fascia_fp_v2 (
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


ALTER TABLE public.t_core_analytics__breakdown_daily_fascia_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__breakdown_daily_fascia_fp_v2; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__breakdown_daily_fascia_fp_v2 AS
 SELECT data,
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


ALTER VIEW public.core_analytics__breakdown_daily_fascia_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__breakdown_monthly_categoria_fp_v2; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__breakdown_monthly_categoria_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);


ALTER TABLE public.t_core_analytics__breakdown_monthly_categoria_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__breakdown_monthly_categoria_fp_v2; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__breakdown_monthly_categoria_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_monthly_categoria_fp_v2;


ALTER VIEW public.core_analytics__breakdown_monthly_categoria_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__breakdown_monthly_famiglia_fp_v2; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__breakdown_monthly_famiglia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);


ALTER TABLE public.t_core_analytics__breakdown_monthly_famiglia_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__breakdown_monthly_famiglia_fp_v2; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__breakdown_monthly_famiglia_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_monthly_famiglia_fp_v2;


ALTER VIEW public.core_analytics__breakdown_monthly_famiglia_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__breakdown_monthly_fascia_fp_v2; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__breakdown_monthly_fascia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);


ALTER TABLE public.t_core_analytics__breakdown_monthly_fascia_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__breakdown_monthly_fascia_fp_v2; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__breakdown_monthly_fascia_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_monthly_fascia_fp_v2;


ALTER VIEW public.core_analytics__breakdown_monthly_fascia_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__breakdown_weekly_categoria_fp_v2; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__breakdown_weekly_categoria_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);


ALTER TABLE public.t_core_analytics__breakdown_weekly_categoria_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__breakdown_weekly_categoria_fp_v2; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__breakdown_weekly_categoria_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_weekly_categoria_fp_v2;


ALTER VIEW public.core_analytics__breakdown_weekly_categoria_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__breakdown_weekly_famiglia_fp_v2; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__breakdown_weekly_famiglia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);


ALTER TABLE public.t_core_analytics__breakdown_weekly_famiglia_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__breakdown_weekly_famiglia_fp_v2; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__breakdown_weekly_famiglia_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_weekly_famiglia_fp_v2;


ALTER VIEW public.core_analytics__breakdown_weekly_famiglia_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__breakdown_weekly_fascia_fp_v2; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__breakdown_weekly_fascia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);


ALTER TABLE public.t_core_analytics__breakdown_weekly_fascia_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__breakdown_weekly_fascia_fp_v2; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__breakdown_weekly_fascia_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_weekly_fascia_fp_v2;


ALTER VIEW public.core_analytics__breakdown_weekly_fascia_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__breakdown_yearly_categoria_fp_v2; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__breakdown_yearly_categoria_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);


ALTER TABLE public.t_core_analytics__breakdown_yearly_categoria_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__breakdown_yearly_categoria_fp_v2; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__breakdown_yearly_categoria_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_yearly_categoria_fp_v2;


ALTER VIEW public.core_analytics__breakdown_yearly_categoria_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__breakdown_yearly_famiglia_fp_v2; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__breakdown_yearly_famiglia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);


ALTER TABLE public.t_core_analytics__breakdown_yearly_famiglia_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__breakdown_yearly_famiglia_fp_v2; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__breakdown_yearly_famiglia_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_yearly_famiglia_fp_v2;


ALTER VIEW public.core_analytics__breakdown_yearly_famiglia_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__breakdown_yearly_fascia_fp_v2; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__breakdown_yearly_fascia_fp_v2 (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_venduta numeric(18,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(18,2) DEFAULT 0 NOT NULL,
    num_articoli integer DEFAULT 0 NOT NULL,
    qty_forecast numeric(18,3)
);


ALTER TABLE public.t_core_analytics__breakdown_yearly_fascia_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__breakdown_yearly_fascia_fp_v2; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__breakdown_yearly_fascia_fp_v2 AS
 SELECT period_start AS data,
    entity_key_lc,
    fascia_prezzo_iva_inc,
    qty_venduta,
    imponibile_netto_tot,
    num_articoli,
    qty_forecast
   FROM public.t_core_analytics__breakdown_yearly_fascia_fp_v2;


ALTER VIEW public.core_analytics__breakdown_yearly_fascia_fp_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: greenhouse_products_normalized; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.greenhouse_products_normalized (
    codart character varying(50) NOT NULL,
    tipo character varying(50),
    fascia character varying(50),
    categoria character varying(50),
    descrizione character varying(255),
    fascia_corretta character varying(50),
    categoria_corretta character varying(50),
    famiglia character varying(100),
    prezzo_iva_esclusa numeric(12,2),
    prezzo_iva_inclusa numeric(12,2),
    fascia_prezzo_iva_inc character varying(50),
    pot_size character varying(20),
    load_timestamp timestamp without time zone DEFAULT now(),
    descrizione_raw character varying(255),
    brand text,
    varieta text,
    colore text,
    note_classificazione text,
    is_classified boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    classification_status text DEFAULT 'new'::text NOT NULL,
    classified_by text,
    classified_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.greenhouse_products_normalized OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__catalog; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__catalog AS
 SELECT DISTINCT 'famiglia'::text AS entity_type,
    greenhouse_products_normalized.famiglia AS entity_key,
    greenhouse_products_normalized.famiglia AS label
   FROM public.greenhouse_products_normalized
  WHERE (greenhouse_products_normalized.famiglia IS NOT NULL)
UNION ALL
 SELECT DISTINCT 'categoria'::text AS entity_type,
    greenhouse_products_normalized.categoria_corretta AS entity_key,
    greenhouse_products_normalized.categoria_corretta AS label
   FROM public.greenhouse_products_normalized
  WHERE (greenhouse_products_normalized.categoria_corretta IS NOT NULL)
UNION ALL
 SELECT DISTINCT 'fascia'::text AS entity_type,
    greenhouse_products_normalized.fascia_corretta AS entity_key,
    greenhouse_products_normalized.fascia_corretta AS label
   FROM public.greenhouse_products_normalized
  WHERE (greenhouse_products_normalized.fascia_corretta IS NOT NULL)
UNION ALL
 SELECT DISTINCT 'fascia_prezzo'::text AS entity_type,
    greenhouse_products_normalized.fascia_prezzo_iva_inc AS entity_key,
    greenhouse_products_normalized.fascia_prezzo_iva_inc AS label
   FROM public.greenhouse_products_normalized
  WHERE (greenhouse_products_normalized.fascia_prezzo_iva_inc IS NOT NULL);


ALTER VIEW public.core_analytics__catalog OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__components_articles; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__components_articles AS
 SELECT famiglia,
    categoria_corretta,
    fascia_corretta,
    fascia_prezzo_iva_inc,
    codart,
    descrizione AS articolo_nome,
    pot_size,
    prezzo_iva_inclusa,
    prezzo_iva_esclusa
   FROM public.greenhouse_products_normalized p
  WHERE (codart IS NOT NULL);


ALTER VIEW public.core_analytics__components_articles OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__seasonality_month; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__seasonality_month (
    entity_type text NOT NULL,
    entity_key_lc text NOT NULL,
    month_num integer NOT NULL,
    avg_qty_per_day numeric(12,3) DEFAULT 0 NOT NULL,
    sum_qty numeric(14,3) DEFAULT 0 NOT NULL,
    avg_rev_per_day numeric(12,2) DEFAULT 0 NOT NULL,
    sum_rev numeric(14,2) DEFAULT 0 NOT NULL,
    n_days integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.t_core_analytics__seasonality_month OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__seasonality_month; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__seasonality_month AS
 SELECT entity_type,
    entity_key_lc,
    month_num,
    avg_qty_per_day,
    sum_qty,
    avg_rev_per_day,
    sum_rev,
    n_days
   FROM public.t_core_analytics__seasonality_month;


ALTER VIEW public.core_analytics__seasonality_month OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: greenhouse_forecast_features_dense; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.greenhouse_forecast_features_dense (
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


ALTER TABLE public.greenhouse_forecast_features_dense OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: greenhouse_forecast_results_v2; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.greenhouse_forecast_results_v2 (
    data date NOT NULL,
    famiglia text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    qty_forecast numeric(12,3) NOT NULL,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.greenhouse_forecast_results_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_daily; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_daily AS
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
     LEFT JOIN public.greenhouse_forecast_results_v2 fc ON (((fc.data = f.data) AND (lower(fc.famiglia) = lower(f.famiglia)) AND (fc.fascia_prezzo_iva_inc = f.fascia_prezzo_iva_inc))));


ALTER VIEW public.core_analytics__series_daily OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__series_daily_categoria; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__series_daily_categoria (
    data date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric,
    is_holiday boolean,
    holiday_name text,
    dow integer
);


ALTER TABLE public.t_core_analytics__series_daily_categoria OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_daily_categoria_lc; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_daily_categoria_lc AS
 SELECT data,
    lower(entity_key) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.t_core_analytics__series_daily_categoria;


ALTER VIEW public.core_analytics__series_daily_categoria_lc OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__series_daily_famiglia; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__series_daily_famiglia (
    data date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric,
    is_holiday boolean,
    holiday_name text,
    dow integer
);


ALTER TABLE public.t_core_analytics__series_daily_famiglia OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_daily_famiglia_lc; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_daily_famiglia_lc AS
 SELECT data,
    lower(entity_key) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.t_core_analytics__series_daily_famiglia;


ALTER VIEW public.core_analytics__series_daily_famiglia_lc OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__series_daily_fascia; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__series_daily_fascia (
    data date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric,
    is_holiday boolean,
    holiday_name text,
    dow integer
);


ALTER TABLE public.t_core_analytics__series_daily_fascia OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_daily_fascia_lc; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_daily_fascia_lc AS
 SELECT data,
    lower(entity_key) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.t_core_analytics__series_daily_fascia;


ALTER VIEW public.core_analytics__series_daily_fascia_lc OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__series_daily_fascia_prezzo; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__series_daily_fascia_prezzo (
    data date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric,
    is_holiday boolean,
    holiday_name text,
    dow integer
);


ALTER TABLE public.t_core_analytics__series_daily_fascia_prezzo OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_daily_fascia_prezzo_lc; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_daily_fascia_prezzo_lc AS
 SELECT data,
    lower(entity_key) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.t_core_analytics__series_daily_fascia_prezzo;


ALTER VIEW public.core_analytics__series_daily_fascia_prezzo_lc OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_daily_total; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_daily_total AS
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


ALTER VIEW public.core_analytics__series_daily_total OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__series_monthly_categoria; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__series_monthly_categoria (
    period_start date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric
);


ALTER TABLE public.t_core_analytics__series_monthly_categoria OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_monthly_categoria_lc; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_monthly_categoria_lc AS
 SELECT period_start AS data,
    lower(btrim(entity_key)) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_monthly_categoria;


ALTER VIEW public.core_analytics__series_monthly_categoria_lc OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__series_monthly_famiglia; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__series_monthly_famiglia (
    period_start date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric
);


ALTER TABLE public.t_core_analytics__series_monthly_famiglia OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_monthly_famiglia_lc; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_monthly_famiglia_lc AS
 SELECT period_start AS data,
    lower(btrim(entity_key)) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_monthly_famiglia;


ALTER VIEW public.core_analytics__series_monthly_famiglia_lc OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__series_monthly_fascia; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__series_monthly_fascia (
    period_start date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric
);


ALTER TABLE public.t_core_analytics__series_monthly_fascia OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_monthly_fascia_lc; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_monthly_fascia_lc AS
 SELECT period_start AS data,
    lower(btrim(entity_key)) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_monthly_fascia;


ALTER VIEW public.core_analytics__series_monthly_fascia_lc OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__series_monthly_fascia_prezzo; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__series_monthly_fascia_prezzo (
    period_start date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric
);


ALTER TABLE public.t_core_analytics__series_monthly_fascia_prezzo OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_monthly_fascia_prezzo_lc; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_monthly_fascia_prezzo_lc AS
 SELECT period_start AS data,
    lower(btrim(entity_key)) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_monthly_fascia_prezzo;


ALTER VIEW public.core_analytics__series_monthly_fascia_prezzo_lc OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__series_weekly_categoria; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__series_weekly_categoria (
    period_start date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric
);


ALTER TABLE public.t_core_analytics__series_weekly_categoria OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_weekly_categoria_lc; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_weekly_categoria_lc AS
 SELECT period_start AS data,
    lower(btrim(entity_key)) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_weekly_categoria;


ALTER VIEW public.core_analytics__series_weekly_categoria_lc OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__series_weekly_famiglia; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__series_weekly_famiglia (
    period_start date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric
);


ALTER TABLE public.t_core_analytics__series_weekly_famiglia OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_weekly_famiglia_lc; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_weekly_famiglia_lc AS
 SELECT period_start AS data,
    lower(btrim(entity_key)) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_weekly_famiglia;


ALTER VIEW public.core_analytics__series_weekly_famiglia_lc OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__series_weekly_fascia; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__series_weekly_fascia (
    period_start date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric
);


ALTER TABLE public.t_core_analytics__series_weekly_fascia OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_weekly_fascia_lc; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_weekly_fascia_lc AS
 SELECT period_start AS data,
    lower(btrim(entity_key)) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_weekly_fascia;


ALTER VIEW public.core_analytics__series_weekly_fascia_lc OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__series_weekly_fascia_prezzo; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__series_weekly_fascia_prezzo (
    period_start date NOT NULL,
    entity_key text NOT NULL,
    qty_venduta_tot numeric,
    imponibile_netto_tot numeric,
    qty_forecast_tot numeric
);


ALTER TABLE public.t_core_analytics__series_weekly_fascia_prezzo OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_weekly_fascia_prezzo_lc; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_weekly_fascia_prezzo_lc AS
 SELECT period_start AS data,
    lower(btrim(entity_key)) AS entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_weekly_fascia_prezzo;


ALTER VIEW public.core_analytics__series_weekly_fascia_prezzo_lc OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__series_yearly_categoria; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__series_yearly_categoria (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    qty_venduta_tot numeric(12,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(12,2) DEFAULT 0 NOT NULL,
    qty_forecast_tot numeric(12,3)
);


ALTER TABLE public.t_core_analytics__series_yearly_categoria OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_yearly_categoria_lc; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_yearly_categoria_lc AS
 SELECT period_start AS data,
    entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_yearly_categoria;


ALTER VIEW public.core_analytics__series_yearly_categoria_lc OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__series_yearly_famiglia; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__series_yearly_famiglia (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    qty_venduta_tot numeric(12,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(12,2) DEFAULT 0 NOT NULL,
    qty_forecast_tot numeric(12,3)
);


ALTER TABLE public.t_core_analytics__series_yearly_famiglia OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_yearly_famiglia_lc; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_yearly_famiglia_lc AS
 SELECT period_start AS data,
    entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_yearly_famiglia;


ALTER VIEW public.core_analytics__series_yearly_famiglia_lc OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__series_yearly_fascia; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__series_yearly_fascia (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    qty_venduta_tot numeric(12,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(12,2) DEFAULT 0 NOT NULL,
    qty_forecast_tot numeric(12,3)
);


ALTER TABLE public.t_core_analytics__series_yearly_fascia OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_yearly_fascia_lc; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_yearly_fascia_lc AS
 SELECT period_start AS data,
    entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_yearly_fascia;


ALTER VIEW public.core_analytics__series_yearly_fascia_lc OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_core_analytics__series_yearly_fascia_prezzo; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_core_analytics__series_yearly_fascia_prezzo (
    period_start date NOT NULL,
    entity_key_lc text NOT NULL,
    qty_venduta_tot numeric(12,3) DEFAULT 0 NOT NULL,
    imponibile_netto_tot numeric(12,2) DEFAULT 0 NOT NULL,
    qty_forecast_tot numeric(12,3)
);


ALTER TABLE public.t_core_analytics__series_yearly_fascia_prezzo OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: core_analytics__series_yearly_fascia_prezzo_lc; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.core_analytics__series_yearly_fascia_prezzo_lc AS
 SELECT period_start AS data,
    entity_key_lc,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot
   FROM public.t_core_analytics__series_yearly_fascia_prezzo;


ALTER VIEW public.core_analytics__series_yearly_fascia_prezzo_lc OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: greenhouse_forecast_windows_v2; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.greenhouse_forecast_windows_v2 AS
 SELECT famiglia,
    fascia_prezzo_iva_inc,
    sum(
        CASE
            WHEN ((data >= (CURRENT_DATE + '1 day'::interval)) AND (data <= (CURRENT_DATE + '3 days'::interval))) THEN qty_forecast
            ELSE (0)::numeric
        END) AS qty_forecast_1_3,
    sum(
        CASE
            WHEN ((data >= (CURRENT_DATE + '4 days'::interval)) AND (data <= (CURRENT_DATE + '10 days'::interval))) THEN qty_forecast
            ELSE (0)::numeric
        END) AS qty_forecast_4_10
   FROM public.greenhouse_forecast_results_v2
  GROUP BY famiglia, fascia_prezzo_iva_inc;


ALTER VIEW public.greenhouse_forecast_windows_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: greenhouse_stock_raw_upload; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.greenhouse_stock_raw_upload (
    data_rilevazione date DEFAULT CURRENT_DATE NOT NULL,
    codart text NOT NULL,
    descrizione text,
    qty_giacenza numeric(12,3) NOT NULL,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.greenhouse_stock_raw_upload OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: greenhouse_stock_enriched; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.greenhouse_stock_enriched AS
 SELECT s.data_rilevazione,
    s.codart,
    s.descrizione AS descrizione_stock,
    s.qty_giacenza,
    p.famiglia,
    p.fascia_prezzo_iva_inc,
    p.pot_size,
    p.fascia_corretta,
    p.categoria_corretta
   FROM (public.greenhouse_stock_raw_upload s
     LEFT JOIN public.greenhouse_products_normalized p ON ((s.codart = (p.codart)::text)));


ALTER VIEW public.greenhouse_stock_enriched OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: greenhouse_stock_family_latest_v2; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.greenhouse_stock_family_latest_v2 AS
 WITH latest_date AS (
         SELECT max(s.data_rilevazione) AS data_rilevazione
           FROM public.greenhouse_stock_raw_upload s
        )
 SELECT e.data_rilevazione,
    e.famiglia,
    e.fascia_prezzo_iva_inc,
    sum(e.qty_giacenza) AS qty_giacenza
   FROM (public.greenhouse_stock_enriched e
     JOIN latest_date ld ON ((e.data_rilevazione = ld.data_rilevazione)))
  WHERE ((e.famiglia IS NOT NULL) AND (e.fascia_prezzo_iva_inc IS NOT NULL))
  GROUP BY e.data_rilevazione, e.famiglia, e.fascia_prezzo_iva_inc
  ORDER BY e.famiglia, e.fascia_prezzo_iva_inc;


ALTER VIEW public.greenhouse_stock_family_latest_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: greenhouse_order_suggestions_v2; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.greenhouse_order_suggestions_v2 AS
 WITH stock AS (
         SELECT greenhouse_stock_family_latest_v2.data_rilevazione,
            greenhouse_stock_family_latest_v2.famiglia,
            greenhouse_stock_family_latest_v2.fascia_prezzo_iva_inc,
            greenhouse_stock_family_latest_v2.qty_giacenza
           FROM public.greenhouse_stock_family_latest_v2
        ), params AS (
         SELECT 1.5 AS safety_factor
        )
 SELECT f.famiglia,
    f.fascia_prezzo_iva_inc,
    f.qty_forecast_1_3 AS demand_lead,
    f.qty_forecast_4_10 AS demand_cycle,
        CASE
            WHEN (s.famiglia IS NULL) THEN false
            ELSE true
        END AS in_assortimento,
    COALESCE(s.qty_giacenza, (0)::numeric) AS qty_giacenza,
    (COALESCE(s.qty_giacenza, (0)::numeric) - f.qty_forecast_1_3) AS stock_after_lead_raw,
    GREATEST((0)::numeric, (COALESCE(s.qty_giacenza, (0)::numeric) - f.qty_forecast_1_3)) AS stock_after_lead,
    (f.qty_forecast_4_10 * p.safety_factor) AS required_on_arrival,
    GREATEST((0)::numeric, ((f.qty_forecast_4_10 * p.safety_factor) - GREATEST((0)::numeric, (COALESCE(s.qty_giacenza, (0)::numeric) - f.qty_forecast_1_3)))) AS qty_da_ordinare,
        CASE
            WHEN (COALESCE(s.qty_giacenza, (0)::numeric) < f.qty_forecast_1_3) THEN true
            ELSE false
        END AS rischio_stockout_prima_di_arrivo
   FROM ((public.greenhouse_forecast_windows_v2 f
     LEFT JOIN stock s ON (((f.famiglia = (s.famiglia)::text) AND (f.fascia_prezzo_iva_inc = (s.fascia_prezzo_iva_inc)::text))))
     CROSS JOIN params p)
  ORDER BY f.famiglia, f.fascia_prezzo_iva_inc;


ALTER VIEW public.greenhouse_order_suggestions_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: greenhouse_sales_family_daily_fact; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.greenhouse_sales_family_daily_fact (
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
    articoli_json jsonb DEFAULT '[]'::jsonb NOT NULL
);


ALTER TABLE public.greenhouse_sales_family_daily_fact OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: greenhouse_sales_family_meta_v2; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.greenhouse_sales_family_meta_v2 AS
 SELECT famiglia,
    fascia_prezzo_iva_inc,
    min(fascia_corretta) AS fascia_corretta,
    min(categoria_corretta) AS categoria_corretta,
    string_agg(DISTINCT ps, ','::text ORDER BY ps) AS pot_sizes_text,
    jsonb_agg(DISTINCT ps) AS pot_sizes_json
   FROM ( SELECT greenhouse_sales_family_daily_fact.famiglia,
            greenhouse_sales_family_daily_fact.fascia_prezzo_iva_inc,
            greenhouse_sales_family_daily_fact.fascia_corretta,
            greenhouse_sales_family_daily_fact.categoria_corretta,
            jsonb_array_elements_text(greenhouse_sales_family_daily_fact.pot_sizes_json) AS ps
           FROM public.greenhouse_sales_family_daily_fact) x
  GROUP BY famiglia, fascia_prezzo_iva_inc;


ALTER VIEW public.greenhouse_sales_family_meta_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: greenhouse_order_suggestions_enriched_v2; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.greenhouse_order_suggestions_enriched_v2 AS
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
   FROM (public.greenhouse_order_suggestions_v2 o
     LEFT JOIN public.greenhouse_sales_family_meta_v2 m ON (((o.famiglia = m.famiglia) AND (o.fascia_prezzo_iva_inc = m.fascia_prezzo_iva_inc))))
  WHERE (o.qty_da_ordinare >= (1)::numeric)
  ORDER BY o.famiglia, o.fascia_prezzo_iva_inc;


ALTER VIEW public.greenhouse_order_suggestions_enriched_v2 OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: dashboard__reorder_suggestions_top; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.dashboard__reorder_suggestions_top AS
 SELECT famiglia,
    fascia_prezzo_iva_inc,
    categoria_corretta,
    fascia_corretta,
    pot_sizes_text,
    qty_giacenza,
    qty_da_ordinare,
    rischio_stockout_prima_di_arrivo,
    demand_lead,
    demand_cycle,
    in_assortimento
   FROM public.greenhouse_order_suggestions_enriched_v2
  WHERE (COALESCE(qty_da_ordinare, (0)::numeric) > (0)::numeric)
  ORDER BY COALESCE(rischio_stockout_prima_di_arrivo, false) DESC, COALESCE(qty_da_ordinare, (0)::numeric) DESC, COALESCE(qty_giacenza, (0)::numeric)
 LIMIT 200;


ALTER VIEW public.dashboard__reorder_suggestions_top OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_dashboard_sales_monthly; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_dashboard_sales_monthly (
    period_start date NOT NULL,
    qty_tot numeric(18,3) DEFAULT 0 NOT NULL,
    imp_tot numeric(18,2) DEFAULT 0 NOT NULL
);


ALTER TABLE public.t_dashboard_sales_monthly OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: dashboard__sales_monthly; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.dashboard__sales_monthly AS
 SELECT period_start AS data,
    qty_tot,
    imp_tot
   FROM public.t_dashboard_sales_monthly;


ALTER VIEW public.dashboard__sales_monthly OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_dashboard_sales_weekly; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_dashboard_sales_weekly (
    period_start date NOT NULL,
    qty_tot numeric(18,3) DEFAULT 0 NOT NULL,
    imp_tot numeric(18,2) DEFAULT 0 NOT NULL
);


ALTER TABLE public.t_dashboard_sales_weekly OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: dashboard__sales_weekly; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.dashboard__sales_weekly AS
 SELECT period_start AS data,
    qty_tot,
    imp_tot
   FROM public.t_dashboard_sales_weekly;


ALTER VIEW public.dashboard__sales_weekly OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_dashboard_sales_yearly; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_dashboard_sales_yearly (
    period_start date NOT NULL,
    qty_tot numeric(18,3) DEFAULT 0 NOT NULL,
    imp_tot numeric(18,2) DEFAULT 0 NOT NULL
);


ALTER TABLE public.t_dashboard_sales_yearly OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: dashboard__sales_yearly; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.dashboard__sales_yearly AS
 SELECT period_start AS data,
    qty_tot,
    imp_tot
   FROM public.t_dashboard_sales_yearly;


ALTER VIEW public.dashboard__sales_yearly OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: etl_runs; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.etl_runs (
    run_id bigint NOT NULL,
    job_name text NOT NULL,
    run_type text NOT NULL,
    status text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    ended_at timestamp with time zone,
    source_system text,
    source_object text,
    from_progressivo bigint,
    to_progressivo bigint,
    from_day date,
    to_day date,
    rows_extracted bigint DEFAULT 0 NOT NULL,
    rows_loaded bigint DEFAULT 0 NOT NULL,
    rows_skipped bigint DEFAULT 0 NOT NULL,
    error_message text,
    meta_json jsonb DEFAULT '{}'::jsonb NOT NULL
);


ALTER TABLE public.etl_runs OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: etl_runs_run_id_seq; Type: SEQUENCE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE SEQUENCE public.etl_runs_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.etl_runs_run_id_seq OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: etl_runs_run_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER SEQUENCE public.etl_runs_run_id_seq OWNED BY public.etl_runs.run_id;


--
-- Name: famiglie_catalog_static; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.famiglie_catalog_static (
    famiglia text NOT NULL,
    famiglia_slug text
);


ALTER TABLE public.famiglie_catalog_static OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: garden_center_settings; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.garden_center_settings (
    id integer DEFAULT 1 NOT NULL,
    city text DEFAULT ''::text NOT NULL,
    lat double precision,
    lon double precision,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT garden_center_settings_singleton CHECK ((id = 1))
);


ALTER TABLE public.garden_center_settings OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: greenbrain_users; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.greenbrain_users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email text NOT NULL,
    hashed_password text NOT NULL,
    full_name text,
    is_active boolean DEFAULT true NOT NULL,
    is_admin boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_login_at timestamp with time zone,
    tenant_code text,
    home_host text,
    home_path text,
    user_role text
);


ALTER TABLE public.greenbrain_users OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: greenhouse_holidays; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.greenhouse_holidays (
    data date NOT NULL,
    is_holiday boolean DEFAULT true NOT NULL,
    holiday_name text
);


ALTER TABLE public.greenhouse_holidays OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: greenhouse_sales_family_daily_dense; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.greenhouse_sales_family_daily_dense (
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
    articoli_json jsonb DEFAULT '[]'::jsonb NOT NULL
);


ALTER TABLE public.greenhouse_sales_family_daily_dense OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: greenhouse_sales_raw_staging; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.greenhouse_sales_raw_staging (
    progressivo bigint NOT NULL,
    codart character varying(50),
    descrizione character varying(255),
    tipo character varying(50),
    fascia character varying(50),
    categoria character varying(50),
    quantita numeric(10,2),
    imponibilenetto numeric(12,2),
    data_movimento date,
    disattivato smallint,
    movim_cassa smallint,
    load_timestamp timestamp without time zone DEFAULT now(),
    etl_run_id bigint
);


ALTER TABLE public.greenhouse_sales_raw_staging OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: greenhouse_series_list_fact; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.greenhouse_series_list_fact (
    famiglia text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    fascia_corretta text,
    categoria_corretta text
);


ALTER TABLE public.greenhouse_series_list_fact OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: greenhouse_weather_daily; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.greenhouse_weather_daily (
    data date NOT NULL,
    tmin_c numeric,
    tmax_c numeric,
    tavg_c numeric,
    rain_mm numeric,
    sun_hours numeric
);


ALTER TABLE public.greenhouse_weather_daily OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: mv_core_analytics__catalog_entities; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.mv_core_analytics__catalog_entities AS
 SELECT 'fascia'::text AS entity_type,
    lower(TRIM(BOTH FROM greenhouse_products_normalized.fascia_corretta)) AS entity_key,
    TRIM(BOTH FROM greenhouse_products_normalized.fascia_corretta) AS label,
    TRIM(BOTH FROM greenhouse_products_normalized.fascia_corretta) AS fascia,
    NULL::text AS categoria,
    NULL::text AS famiglia,
    NULL::text AS fascia_prezzo
   FROM public.greenhouse_products_normalized
  WHERE (greenhouse_products_normalized.fascia_corretta IS NOT NULL)
  GROUP BY greenhouse_products_normalized.fascia_corretta
UNION ALL
 SELECT 'categoria'::text AS entity_type,
    lower(TRIM(BOTH FROM greenhouse_products_normalized.categoria_corretta)) AS entity_key,
    TRIM(BOTH FROM greenhouse_products_normalized.categoria_corretta) AS label,
    max(TRIM(BOTH FROM greenhouse_products_normalized.fascia_corretta)) AS fascia,
    TRIM(BOTH FROM greenhouse_products_normalized.categoria_corretta) AS categoria,
    NULL::text AS famiglia,
    NULL::text AS fascia_prezzo
   FROM public.greenhouse_products_normalized
  WHERE (greenhouse_products_normalized.categoria_corretta IS NOT NULL)
  GROUP BY greenhouse_products_normalized.categoria_corretta
UNION ALL
 SELECT 'famiglia'::text AS entity_type,
    lower(TRIM(BOTH FROM greenhouse_products_normalized.famiglia)) AS entity_key,
    TRIM(BOTH FROM greenhouse_products_normalized.famiglia) AS label,
    max(TRIM(BOTH FROM greenhouse_products_normalized.fascia_corretta)) AS fascia,
    max(TRIM(BOTH FROM greenhouse_products_normalized.categoria_corretta)) AS categoria,
    TRIM(BOTH FROM greenhouse_products_normalized.famiglia) AS famiglia,
    NULL::text AS fascia_prezzo
   FROM public.greenhouse_products_normalized
  WHERE (greenhouse_products_normalized.famiglia IS NOT NULL)
  GROUP BY greenhouse_products_normalized.famiglia
UNION ALL
 SELECT 'fascia_prezzo'::text AS entity_type,
    lower(TRIM(BOTH FROM greenhouse_products_normalized.fascia_prezzo_iva_inc)) AS entity_key,
    TRIM(BOTH FROM greenhouse_products_normalized.fascia_prezzo_iva_inc) AS label,
    max(TRIM(BOTH FROM greenhouse_products_normalized.fascia_corretta)) AS fascia,
    max(TRIM(BOTH FROM greenhouse_products_normalized.categoria_corretta)) AS categoria,
    max(TRIM(BOTH FROM greenhouse_products_normalized.famiglia)) AS famiglia,
    TRIM(BOTH FROM greenhouse_products_normalized.fascia_prezzo_iva_inc) AS fascia_prezzo
   FROM public.greenhouse_products_normalized
  WHERE (greenhouse_products_normalized.fascia_prezzo_iva_inc IS NOT NULL)
  GROUP BY greenhouse_products_normalized.fascia_prezzo_iva_inc;


ALTER VIEW public.mv_core_analytics__catalog_entities OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: mv_core_analytics__series_daily_categoria; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.mv_core_analytics__series_daily_categoria AS
 SELECT data,
    entity_key,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.t_core_analytics__series_daily_categoria;


ALTER VIEW public.mv_core_analytics__series_daily_categoria OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: mv_core_analytics__series_daily_fascia; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.mv_core_analytics__series_daily_fascia AS
 SELECT data,
    entity_key,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.t_core_analytics__series_daily_fascia;


ALTER VIEW public.mv_core_analytics__series_daily_fascia OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: mv_core_analytics__series_daily_fascia_prezzo; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.mv_core_analytics__series_daily_fascia_prezzo AS
 SELECT data,
    entity_key,
    qty_venduta_tot,
    imponibile_netto_tot,
    qty_forecast_tot,
    is_holiday,
    holiday_name,
    dow
   FROM public.t_core_analytics__series_daily_fascia_prezzo;


ALTER VIEW public.mv_core_analytics__series_daily_fascia_prezzo OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: mv_famiglie_catalog; Type: MATERIALIZED VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE MATERIALIZED VIEW public.mv_famiglie_catalog AS
 SELECT DISTINCT lower(TRIM(BOTH FROM famiglia)) AS famiglia,
    replace(lower(TRIM(BOTH FROM famiglia)), ' '::text, '-'::text) AS famiglia_slug
   FROM public.greenhouse_forecast_features_dense
  WITH NO DATA;


ALTER MATERIALIZED VIEW public.mv_famiglie_catalog OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: ops_parquet_export_runs; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.ops_parquet_export_runs (
    run_id bigint NOT NULL,
    dataset text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    ended_at timestamp with time zone,
    status text DEFAULT 'running'::text NOT NULL,
    from_day date,
    to_day date,
    n_families integer,
    n_files integer,
    n_rows bigint,
    error_message text,
    meta jsonb DEFAULT '{}'::jsonb NOT NULL
);


ALTER TABLE public.ops_parquet_export_runs OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: ops_parquet_export_runs_run_id_seq; Type: SEQUENCE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE SEQUENCE public.ops_parquet_export_runs_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ops_parquet_export_runs_run_id_seq OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: ops_parquet_export_runs_run_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER SEQUENCE public.ops_parquet_export_runs_run_id_seq OWNED BY public.ops_parquet_export_runs.run_id;


--
-- Name: ops_parquet_export_state; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.ops_parquet_export_state (
    id integer DEFAULT 1 NOT NULL,
    dataset text NOT NULL,
    export_mode text NOT NULL,
    overwrite_days integer DEFAULT 40 NOT NULL,
    last_success_run_at timestamp with time zone,
    last_success_day date,
    storage_prefix text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.ops_parquet_export_state OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_ops_pipeline_monitor; Type: TABLE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TABLE public.t_ops_pipeline_monitor (
    id integer NOT NULL,
    snap_ts timestamp with time zone DEFAULT now() NOT NULL,
    ok boolean DEFAULT false NOT NULL
);


ALTER TABLE public.t_ops_pipeline_monitor OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_ops_pipeline_monitor_id_seq; Type: SEQUENCE; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE SEQUENCE public.t_ops_pipeline_monitor_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.t_ops_pipeline_monitor_id_seq OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: t_ops_pipeline_monitor_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER SEQUENCE public.t_ops_pipeline_monitor_id_seq OWNED BY public.t_ops_pipeline_monitor.id;


--
-- Name: v_famiglie_catalog; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.v_famiglie_catalog AS
 SELECT famiglia,
    replace(lower(TRIM(BOTH FROM famiglia)), ' '::text, '-'::text) AS famiglia_slug
   FROM public.mv_famiglie_catalog;


ALTER VIEW public.v_famiglie_catalog OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: v_ops_pipeline_status; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.v_ops_pipeline_status AS
 SELECT id,
    snap_ts,
    ok
   FROM public.t_ops_pipeline_monitor;


ALTER VIEW public.v_ops_pipeline_status OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: v_products_unclassified; Type: VIEW; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE VIEW public.v_products_unclassified AS
 SELECT r.codart,
    max((r.descrizione)::text) AS descrizione_raw,
    max((r.tipo)::text) AS tipo,
    min(r.data_movimento) AS first_seen_date,
    max(r.data_movimento) AS last_seen_date,
    count(*) AS rows_n,
    (sum(COALESCE(r.quantita, (0)::numeric)))::numeric(14,2) AS qty_tot
   FROM (public.greenhouse_sales_raw_staging r
     LEFT JOIN public.greenhouse_products_normalized p ON (((p.codart)::text = (r.codart)::text)))
  WHERE (((COALESCE(r.codart, ''::character varying))::text <> ''::text) AND ((p.codart IS NULL) OR (COALESCE(p.is_classified, false) = false)))
  GROUP BY r.codart;


ALTER VIEW public.v_products_unclassified OWNER TO greenbrain_cliente_reale_demo;

--
-- Name: _runtime_bootstrap id; Type: DEFAULT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public._runtime_bootstrap ALTER COLUMN id SET DEFAULT nextval('public._runtime_bootstrap_id_seq'::regclass);


--
-- Name: calendar_events id; Type: DEFAULT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.calendar_events ALTER COLUMN id SET DEFAULT nextval('public.calendar_events_id_seq'::regclass);


--
-- Name: etl_runs run_id; Type: DEFAULT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.etl_runs ALTER COLUMN run_id SET DEFAULT nextval('public.etl_runs_run_id_seq'::regclass);


--
-- Name: ops_parquet_export_runs run_id; Type: DEFAULT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.ops_parquet_export_runs ALTER COLUMN run_id SET DEFAULT nextval('public.ops_parquet_export_runs_run_id_seq'::regclass);


--
-- Name: t_ops_pipeline_monitor id; Type: DEFAULT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.t_ops_pipeline_monitor ALTER COLUMN id SET DEFAULT nextval('public.t_ops_pipeline_monitor_id_seq'::regclass);


--
-- Data for Name: family_run_log_v1; Type: TABLE DATA; Schema: ml_ops; Owner: greenbrain_cliente_reale_demo
--

COPY ml_ops.family_run_log_v1 (family_run_id, pipeline_run_id, job_type, family_name, demand_class_final, model_code, started_at, finished_at, status, rows_written, artifact_path, error_message, error_trace) FROM stdin;
\.


--
-- Data for Name: pipeline_run_log_v1; Type: TABLE DATA; Schema: ml_ops; Owner: greenbrain_cliente_reale_demo
--

COPY ml_ops.pipeline_run_log_v1 (run_id, job_type, trigger_mode, status, started_at, finished_at, duration_min, host_name, rows_processed, error_message, git_sha, notes) FROM stdin;
\.


--
-- Data for Name: _runtime_bootstrap; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public._runtime_bootstrap (id, wave, applied_at, note) FROM stdin;
1	wave-7a	2026-04-10 15:47:00.77326+00	infrastructure bootstrap: DB connection verified, schema DDL deferred to Wave 7B
\.


--
-- Data for Name: calendar_events; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.calendar_events (id, date, name, impact_level) FROM stdin;
\.


--
-- Data for Name: etl_runs; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.etl_runs (run_id, job_name, run_type, status, started_at, ended_at, source_system, source_object, from_progressivo, to_progressivo, from_day, to_day, rows_extracted, rows_loaded, rows_skipped, error_message, meta_json) FROM stdin;
\.


--
-- Data for Name: famiglie_catalog_static; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.famiglie_catalog_static (famiglia, famiglia_slug) FROM stdin;
\.


--
-- Data for Name: garden_center_settings; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.garden_center_settings (id, city, lat, lon, updated_at) FROM stdin;
1		\N	\N	2026-04-10 15:47:01.573651+00
\.


--
-- Data for Name: greenbrain_users; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.greenbrain_users (id, email, hashed_password, full_name, is_active, is_admin, created_at, last_login_at, tenant_code, home_host, home_path, user_role) FROM stdin;
3ea0b160-e2d3-4f8c-b538-36be0e16010c	admin@cliente-reale-demo.local	$2b$12$rUS9ENqudHMFeNv/aEu1a.T30osPNmgnTn53i2bEHO9EbSwExPsOq	Admin Cliente Reale Demo	t	t	2026-04-10 15:47:30.38455+00	2026-04-12 20:21:36.851912+00	cliente-reale-demo	cliente-reale-demo.greenbrain.it	/dashboard	tenant_admin
\.


--
-- Data for Name: greenhouse_forecast_features_dense; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.greenhouse_forecast_features_dense (data, famiglia, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, fascia_corretta, categoria_corretta, pot_sizes_text, pot_sizes_json, articoli_inclusi, articoli_json, tmin_c, tmax_c, tavg_c, rain_mm, sun_hours, is_holiday, holiday_name, dow, week_num, month_num, year_num, qty_lag_1, qty_lag_2, qty_lag_3, qty_lag_7, qty_lag_10, qty_lag_14, qty_ma_3, qty_ma_7, qty_ma_10, qty_ma_14, qty_ma_28, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: greenhouse_forecast_results_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.greenhouse_forecast_results_v2 (data, famiglia, fascia_prezzo_iva_inc, qty_forecast, created_at) FROM stdin;
\.


--
-- Data for Name: greenhouse_holidays; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.greenhouse_holidays (data, is_holiday, holiday_name) FROM stdin;
\.


--
-- Data for Name: greenhouse_products_normalized; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.greenhouse_products_normalized (codart, tipo, fascia, categoria, descrizione, fascia_corretta, categoria_corretta, famiglia, prezzo_iva_esclusa, prezzo_iva_inclusa, fascia_prezzo_iva_inc, pot_size, load_timestamp, descrizione_raw, brand, varieta, colore, note_classificazione, is_classified, is_active, classification_status, classified_by, classified_at, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: greenhouse_sales_family_daily_dense; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.greenhouse_sales_family_daily_dense (data, famiglia, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, fascia_corretta, categoria_corretta, pot_sizes_text, pot_sizes_json, articoli_inclusi, articoli_json) FROM stdin;
\.


--
-- Data for Name: greenhouse_sales_family_daily_fact; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.greenhouse_sales_family_daily_fact (data, famiglia, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, fascia_corretta, categoria_corretta, pot_sizes_text, pot_sizes_json, articoli_inclusi, articoli_json) FROM stdin;
\.


--
-- Data for Name: greenhouse_sales_raw_staging; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.greenhouse_sales_raw_staging (progressivo, codart, descrizione, tipo, fascia, categoria, quantita, imponibilenetto, data_movimento, disattivato, movim_cassa, load_timestamp, etl_run_id) FROM stdin;
\.


--
-- Data for Name: greenhouse_series_list_fact; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.greenhouse_series_list_fact (famiglia, fascia_prezzo_iva_inc, fascia_corretta, categoria_corretta) FROM stdin;
\.


--
-- Data for Name: greenhouse_stock_raw_upload; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.greenhouse_stock_raw_upload (data_rilevazione, codart, descrizione, qty_giacenza, created_at) FROM stdin;
\.


--
-- Data for Name: greenhouse_weather_daily; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.greenhouse_weather_daily (data, tmin_c, tmax_c, tavg_c, rain_mm, sun_hours) FROM stdin;
\.


--
-- Data for Name: ops_parquet_export_runs; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.ops_parquet_export_runs (run_id, dataset, started_at, ended_at, status, from_day, to_day, n_families, n_files, n_rows, error_message, meta) FROM stdin;
\.


--
-- Data for Name: ops_parquet_export_state; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.ops_parquet_export_state (id, dataset, export_mode, overwrite_days, last_success_run_at, last_success_day, storage_prefix, created_at, updated_at) FROM stdin;
1	features_dense_ml_clean	full	40	\N	\N	features_dense/v1	2026-04-10 15:47:01.592206+00	2026-04-10 15:47:01.592206+00
\.


--
-- Data for Name: t_core_analytics__breakdown_daily_categoria_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__breakdown_daily_categoria_fp_v2 (data, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, is_holiday, holiday_name, dow, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_daily_famiglia_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__breakdown_daily_famiglia_fp_v2 (data, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, is_holiday, holiday_name, dow, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_daily_fascia_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__breakdown_daily_fascia_fp_v2 (data, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, is_holiday, holiday_name, dow, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_monthly_categoria_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__breakdown_monthly_categoria_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_monthly_famiglia_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__breakdown_monthly_famiglia_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_monthly_fascia_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__breakdown_monthly_fascia_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_weekly_categoria_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__breakdown_weekly_categoria_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_weekly_famiglia_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__breakdown_weekly_famiglia_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_weekly_fascia_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__breakdown_weekly_fascia_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_yearly_categoria_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__breakdown_yearly_categoria_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_yearly_famiglia_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__breakdown_yearly_famiglia_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__breakdown_yearly_fascia_fp_v2; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__breakdown_yearly_fascia_fp_v2 (period_start, entity_key_lc, fascia_prezzo_iva_inc, qty_venduta, imponibile_netto_tot, num_articoli, qty_forecast) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__seasonality_month; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__seasonality_month (entity_type, entity_key_lc, month_num, avg_qty_per_day, sum_qty, avg_rev_per_day, sum_rev, n_days) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_daily_categoria; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__series_daily_categoria (data, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot, is_holiday, holiday_name, dow) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_daily_famiglia; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__series_daily_famiglia (data, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot, is_holiday, holiday_name, dow) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_daily_fascia; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__series_daily_fascia (data, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot, is_holiday, holiday_name, dow) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_daily_fascia_prezzo; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__series_daily_fascia_prezzo (data, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot, is_holiday, holiday_name, dow) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_monthly_categoria; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__series_monthly_categoria (period_start, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_monthly_famiglia; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__series_monthly_famiglia (period_start, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_monthly_fascia; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__series_monthly_fascia (period_start, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_monthly_fascia_prezzo; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__series_monthly_fascia_prezzo (period_start, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_weekly_categoria; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__series_weekly_categoria (period_start, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_weekly_famiglia; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__series_weekly_famiglia (period_start, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_weekly_fascia; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__series_weekly_fascia (period_start, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_weekly_fascia_prezzo; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__series_weekly_fascia_prezzo (period_start, entity_key, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_yearly_categoria; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__series_yearly_categoria (period_start, entity_key_lc, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_yearly_famiglia; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__series_yearly_famiglia (period_start, entity_key_lc, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_yearly_fascia; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__series_yearly_fascia (period_start, entity_key_lc, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot) FROM stdin;
\.


--
-- Data for Name: t_core_analytics__series_yearly_fascia_prezzo; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_core_analytics__series_yearly_fascia_prezzo (period_start, entity_key_lc, qty_venduta_tot, imponibile_netto_tot, qty_forecast_tot) FROM stdin;
\.


--
-- Data for Name: t_dashboard_sales_monthly; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_dashboard_sales_monthly (period_start, qty_tot, imp_tot) FROM stdin;
\.


--
-- Data for Name: t_dashboard_sales_weekly; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_dashboard_sales_weekly (period_start, qty_tot, imp_tot) FROM stdin;
\.


--
-- Data for Name: t_dashboard_sales_yearly; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_dashboard_sales_yearly (period_start, qty_tot, imp_tot) FROM stdin;
\.


--
-- Data for Name: t_ops_pipeline_monitor; Type: TABLE DATA; Schema: public; Owner: greenbrain_cliente_reale_demo
--

COPY public.t_ops_pipeline_monitor (id, snap_ts, ok) FROM stdin;
\.


--
-- Name: _runtime_bootstrap_id_seq; Type: SEQUENCE SET; Schema: public; Owner: greenbrain_cliente_reale_demo
--

SELECT pg_catalog.setval('public._runtime_bootstrap_id_seq', 33, true);


--
-- Name: calendar_events_id_seq; Type: SEQUENCE SET; Schema: public; Owner: greenbrain_cliente_reale_demo
--

SELECT pg_catalog.setval('public.calendar_events_id_seq', 1, false);


--
-- Name: etl_runs_run_id_seq; Type: SEQUENCE SET; Schema: public; Owner: greenbrain_cliente_reale_demo
--

SELECT pg_catalog.setval('public.etl_runs_run_id_seq', 1, false);


--
-- Name: ops_parquet_export_runs_run_id_seq; Type: SEQUENCE SET; Schema: public; Owner: greenbrain_cliente_reale_demo
--

SELECT pg_catalog.setval('public.ops_parquet_export_runs_run_id_seq', 1, false);


--
-- Name: t_ops_pipeline_monitor_id_seq; Type: SEQUENCE SET; Schema: public; Owner: greenbrain_cliente_reale_demo
--

SELECT pg_catalog.setval('public.t_ops_pipeline_monitor_id_seq', 1, false);


--
-- Name: family_run_log_v1 family_run_log_v1_pkey; Type: CONSTRAINT; Schema: ml_ops; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY ml_ops.family_run_log_v1
    ADD CONSTRAINT family_run_log_v1_pkey PRIMARY KEY (family_run_id);


--
-- Name: pipeline_run_log_v1 pipeline_run_log_v1_pkey; Type: CONSTRAINT; Schema: ml_ops; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY ml_ops.pipeline_run_log_v1
    ADD CONSTRAINT pipeline_run_log_v1_pkey PRIMARY KEY (run_id);


--
-- Name: _runtime_bootstrap _runtime_bootstrap_pkey; Type: CONSTRAINT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public._runtime_bootstrap
    ADD CONSTRAINT _runtime_bootstrap_pkey PRIMARY KEY (id);


--
-- Name: calendar_events calendar_events_pkey; Type: CONSTRAINT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.calendar_events
    ADD CONSTRAINT calendar_events_pkey PRIMARY KEY (id);


--
-- Name: etl_runs etl_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.etl_runs
    ADD CONSTRAINT etl_runs_pkey PRIMARY KEY (run_id);


--
-- Name: garden_center_settings garden_center_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.garden_center_settings
    ADD CONSTRAINT garden_center_settings_pkey PRIMARY KEY (id);


--
-- Name: greenbrain_users greenbrain_users_email_key; Type: CONSTRAINT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.greenbrain_users
    ADD CONSTRAINT greenbrain_users_email_key UNIQUE (email);


--
-- Name: greenbrain_users greenbrain_users_pkey; Type: CONSTRAINT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.greenbrain_users
    ADD CONSTRAINT greenbrain_users_pkey PRIMARY KEY (id);


--
-- Name: greenhouse_holidays greenhouse_holidays_pkey; Type: CONSTRAINT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.greenhouse_holidays
    ADD CONSTRAINT greenhouse_holidays_pkey PRIMARY KEY (data);


--
-- Name: greenhouse_sales_family_daily_dense greenhouse_sales_family_daily_dense_pkey; Type: CONSTRAINT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.greenhouse_sales_family_daily_dense
    ADD CONSTRAINT greenhouse_sales_family_daily_dense_pkey PRIMARY KEY (data, famiglia, fascia_prezzo_iva_inc);


--
-- Name: greenhouse_sales_raw_staging greenhouse_sales_raw_staging_pkey; Type: CONSTRAINT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.greenhouse_sales_raw_staging
    ADD CONSTRAINT greenhouse_sales_raw_staging_pkey PRIMARY KEY (progressivo);


--
-- Name: greenhouse_series_list_fact greenhouse_series_list_fact_pkey; Type: CONSTRAINT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.greenhouse_series_list_fact
    ADD CONSTRAINT greenhouse_series_list_fact_pkey PRIMARY KEY (famiglia, fascia_prezzo_iva_inc);


--
-- Name: greenhouse_stock_raw_upload greenhouse_stock_raw_upload_pkey; Type: CONSTRAINT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.greenhouse_stock_raw_upload
    ADD CONSTRAINT greenhouse_stock_raw_upload_pkey PRIMARY KEY (data_rilevazione, codart);


--
-- Name: greenhouse_weather_daily greenhouse_weather_daily_pkey; Type: CONSTRAINT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.greenhouse_weather_daily
    ADD CONSTRAINT greenhouse_weather_daily_pkey PRIMARY KEY (data);


--
-- Name: ops_parquet_export_runs ops_parquet_export_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.ops_parquet_export_runs
    ADD CONSTRAINT ops_parquet_export_runs_pkey PRIMARY KEY (run_id);


--
-- Name: ops_parquet_export_state ops_parquet_export_state_pkey; Type: CONSTRAINT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.ops_parquet_export_state
    ADD CONSTRAINT ops_parquet_export_state_pkey PRIMARY KEY (id);


--
-- Name: t_ops_pipeline_monitor t_ops_pipeline_monitor_pkey; Type: CONSTRAINT; Schema: public; Owner: greenbrain_cliente_reale_demo
--

ALTER TABLE ONLY public.t_ops_pipeline_monitor
    ADD CONSTRAINT t_ops_pipeline_monitor_pkey PRIMARY KEY (id);


--
-- Name: greenbrain_users_email_idx; Type: INDEX; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE INDEX greenbrain_users_email_idx ON public.greenbrain_users USING btree (email);


--
-- Name: idx_dense_data; Type: INDEX; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE INDEX idx_dense_data ON public.greenhouse_sales_family_daily_dense USING btree (data);


--
-- Name: idx_dense_series; Type: INDEX; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE INDEX idx_dense_series ON public.greenhouse_sales_family_daily_dense USING btree (famiglia, fascia_prezzo_iva_inc);


--
-- Name: idx_etl_runs_job_started; Type: INDEX; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE INDEX idx_etl_runs_job_started ON public.etl_runs USING btree (job_name, started_at DESC);


--
-- Name: idx_etl_runs_status; Type: INDEX; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE INDEX idx_etl_runs_status ON public.etl_runs USING btree (status);


--
-- Name: idx_products_normalized_famiglia; Type: INDEX; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE INDEX idx_products_normalized_famiglia ON public.greenhouse_products_normalized USING btree (famiglia);


--
-- Name: idx_products_normalized_is_classified; Type: INDEX; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE INDEX idx_products_normalized_is_classified ON public.greenhouse_products_normalized USING btree (is_classified);


--
-- Name: idx_sales_raw_staging_codart; Type: INDEX; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE INDEX idx_sales_raw_staging_codart ON public.greenhouse_sales_raw_staging USING btree (codart);


--
-- Name: idx_sales_raw_staging_data; Type: INDEX; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE INDEX idx_sales_raw_staging_data ON public.greenhouse_sales_raw_staging USING btree (data_movimento);


--
-- Name: greenhouse_products_normalized trg_products_normalized_touch; Type: TRIGGER; Schema: public; Owner: greenbrain_cliente_reale_demo
--

CREATE TRIGGER trg_products_normalized_touch BEFORE UPDATE ON public.greenhouse_products_normalized FOR EACH ROW EXECUTE FUNCTION public.gb_touch_updated_at();


--
-- PostgreSQL database dump complete
--

\unrestrict 6gkfZkb2BfWJ8zQOgMQKszzrTgr6jZD31VarZC8wdFW4BVgYYvApyknrPhgWR5x

