-- GreenBrain Client Runtime — Wave 7B.2-G Entity Summary
--
-- STATUS: PLANNED
--
-- Scope: exactly 1 endpoint:
--   /api/v1/analytics/entity-summary
--
-- Backend RPC:
--   core_analytics__entity_hierarchy_tree_v1(
--     p_entity_type,
--     p_entity_key,
--     p_date_from,
--     p_date_to,
--     p_top_n,
--     p_fascia,
--     p_categoria,
--     p_famiglia,
--     p_fascia_prezzo
--   )
--
-- Objects:
--   1 function
--
-- Dependencies already present:
--   - public.core_analytics__components_articles   [Wave 7B.2-A]
--
-- No new tables.
-- No new views.
-- No extensions.
-- No matviews.
-- No Supabase-specific schemas.
--
-- Expected behavior with empty client-runtime data:
--   HTTP 200 with a JSON payload whose tree is [] and totals are zero-like.
--

SET search_path = public;

CREATE OR REPLACE FUNCTION public.core_analytics__entity_hierarchy_tree_v1(
    p_entity_type text,
    p_entity_key text,
    p_date_from date,
    p_date_to date,
    p_top_n integer,
    p_fascia text DEFAULT NULL::text,
    p_categoria text DEFAULT NULL::text,
    p_famiglia text DEFAULT NULL::text,
    p_fascia_prezzo text DEFAULT NULL::text
) RETURNS jsonb
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

