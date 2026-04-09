-- GreenBrain Client Runtime — Wave 7B.2-A Catalog Schema Contract
--
-- STATUS: PLANNED — not yet applied to client-runtime postgres
--
-- Scope: exactly the 3 catalog endpoints:
--   /api/v1/catalog/search   → core_analytics__search_catalog_rich()
--   /api/v1/catalog/children → core_analytics__catalog_children()
--   /api/v1/catalog/list     → core_analytics__list_catalog()
--
-- Object count: 8
--   1 extension  (pg_trgm — standard PostgreSQL, required for similarity())
--   1 table      (greenhouse_products_normalized — root of all 3 function chains)
--   3 views      (components_articles, catalog_entities, catalog)
--   3 functions  (search_catalog_rich, catalog_children, list_catalog)
--
-- Deliberate deviations from dev/Supabase schema (documented):
--
--   [DEV-1] mv_core_analytics__catalog_entities is a MATERIALIZED VIEW in dev.
--           Created here as a regular VIEW with the same query body.
--           Rationale: matviews require a refresh pipeline (pg_cron or manual REFRESH).
--           A regular VIEW is always current with the base table and needs no
--           infrastructure. Query result is identical. The function body is unchanged.
--
--   [DEV-2] core_analytics__catalog VIEW in dev references greenhouse_forecast_features_dense
--           (a 37-column ML features table). That table is an ML pipeline output artifact
--           and is not the canonical product catalog.
--           Created here as a VIEW on greenhouse_products_normalized instead.
--           The distinct families/categories/fascia/fascia_prezzo values are identical
--           in both sources at runtime. Avoids adding an ML-specific table to the schema.
--
-- All function bodies are extracted VERBATIM from sql/schema/current-schema.sql.
-- No business logic changes.
--
-- Apply after wave_7b1_planned.sql (01_bootstrap.sql + 02_schema_7b1.sql must already exist).
-- To apply as init script:
--   cp wave_7b2a_planned.sql /path/to/client-runtime/sql/init/03_schema_7b2a.sql
-- Then full restart:
--   docker-compose down && docker volume rm docker_postgres_data && docker-compose up -d
--

SET search_path = public;


-- ============================================================
-- SECTION 1: EXTENSION
-- pg_trgm is a standard PostgreSQL extension (not Supabase-specific).
-- Required for similarity() function and the % trigram operator used
-- inside core_analytics__search_catalog_rich.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


-- ============================================================
-- SECTION 2: BASE TABLE
-- greenhouse_products_normalized — canonical product catalog.
-- Root dependency for ALL three catalog functions.
-- Schema verified against sql/schema/current-schema.sql.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.greenhouse_products_normalized (
    codart                character varying(50)  NOT NULL,
    tipo                  character varying(50),
    fascia                character varying(50),
    categoria             character varying(50),
    descrizione           character varying(255),
    fascia_corretta       character varying(50),
    categoria_corretta    character varying(50),
    famiglia              character varying(100),
    prezzo_iva_esclusa    numeric(12,2),
    prezzo_iva_inclusa    numeric(12,2),
    fascia_prezzo_iva_inc character varying(50),
    pot_size              character varying(20),
    load_timestamp        timestamp without time zone DEFAULT now()
);


-- ============================================================
-- SECTION 3: VIEW — core_analytics__components_articles
-- Dependency of: catalog_children, search_catalog_rich
-- Extracted verbatim from dev schema (it already targets the t_ table directly).
-- ============================================================

CREATE OR REPLACE VIEW public.core_analytics__components_articles AS
    SELECT famiglia AS famiglia,
           categoria_corretta,
           fascia_corretta,
           fascia_prezzo_iva_inc,
           codart,
           descrizione        AS articolo_nome,
           pot_size,
           prezzo_iva_inclusa,
           prezzo_iva_esclusa
      FROM public.greenhouse_products_normalized p
     WHERE codart IS NOT NULL;


-- ============================================================
-- SECTION 4: VIEW — mv_core_analytics__catalog_entities
-- Dependency of: search_catalog_rich
--
-- [DEV-1] In dev this is a MATERIALIZED VIEW named mv_core_analytics__catalog_entities.
-- Created here as a regular VIEW with the same name and identical query body.
-- The function core_analytics__search_catalog_rich references it by name —
-- no function body change required.
-- ============================================================

CREATE OR REPLACE VIEW public.mv_core_analytics__catalog_entities AS
    SELECT 'fascia'::text AS entity_type,
           lower(trim(both from fascia_corretta)) AS entity_key,
           trim(both from fascia_corretta)        AS label,
           trim(both from fascia_corretta)        AS fascia,
           NULL::text                             AS categoria,
           NULL::text                             AS famiglia,
           NULL::text                             AS fascia_prezzo
      FROM public.greenhouse_products_normalized
     WHERE fascia_corretta IS NOT NULL
     GROUP BY fascia_corretta

    UNION ALL

    SELECT 'categoria'::text AS entity_type,
           lower(trim(both from categoria_corretta)) AS entity_key,
           trim(both from categoria_corretta)        AS label,
           max(trim(both from fascia_corretta))      AS fascia,
           trim(both from categoria_corretta)        AS categoria,
           NULL::text                                AS famiglia,
           NULL::text                                AS fascia_prezzo
      FROM public.greenhouse_products_normalized
     WHERE categoria_corretta IS NOT NULL
     GROUP BY categoria_corretta

    UNION ALL

    SELECT 'famiglia'::text AS entity_type,
           lower(trim(both from famiglia)) AS entity_key,
           trim(both from famiglia)        AS label,
           max(trim(both from fascia_corretta))    AS fascia,
           max(trim(both from categoria_corretta)) AS categoria,
           trim(both from famiglia)                AS famiglia,
           NULL::text                              AS fascia_prezzo
      FROM public.greenhouse_products_normalized
     WHERE famiglia IS NOT NULL
     GROUP BY famiglia

    UNION ALL

    SELECT 'fascia_prezzo'::text AS entity_type,
           lower(trim(both from fascia_prezzo_iva_inc)) AS entity_key,
           trim(both from fascia_prezzo_iva_inc)        AS label,
           max(trim(both from fascia_corretta))         AS fascia,
           max(trim(both from categoria_corretta))      AS categoria,
           max(trim(both from famiglia))                AS famiglia,
           trim(both from fascia_prezzo_iva_inc)        AS fascia_prezzo
      FROM public.greenhouse_products_normalized
     WHERE fascia_prezzo_iva_inc IS NOT NULL
     GROUP BY fascia_prezzo_iva_inc;


-- ============================================================
-- SECTION 5: VIEW — core_analytics__catalog
-- Dependency of: list_catalog
--
-- [DEV-2] In dev this VIEW references greenhouse_forecast_features_dense
-- (an ML feature-engineering table with 37 columns, not a product catalog table).
-- Rewritten here to use greenhouse_products_normalized as the source.
-- The distinct entity_key values are equivalent at runtime.
-- Avoids adding a 37-column ML artifact table to the client-runtime schema.
-- ============================================================

CREATE OR REPLACE VIEW public.core_analytics__catalog AS
    SELECT DISTINCT 'famiglia'::text AS entity_type,
                    famiglia         AS entity_key,
                    famiglia         AS label
      FROM public.greenhouse_products_normalized
     WHERE famiglia IS NOT NULL

    UNION ALL

    SELECT DISTINCT 'categoria'::text AS entity_type,
                    categoria_corretta AS entity_key,
                    categoria_corretta AS label
      FROM public.greenhouse_products_normalized
     WHERE categoria_corretta IS NOT NULL

    UNION ALL

    SELECT DISTINCT 'fascia'::text AS entity_type,
                    fascia_corretta AS entity_key,
                    fascia_corretta AS label
      FROM public.greenhouse_products_normalized
     WHERE fascia_corretta IS NOT NULL

    UNION ALL

    SELECT DISTINCT 'fascia_prezzo'::text AS entity_type,
                    fascia_prezzo_iva_inc AS entity_key,
                    fascia_prezzo_iva_inc AS label
      FROM public.greenhouse_products_normalized
     WHERE fascia_prezzo_iva_inc IS NOT NULL;


-- ============================================================
-- SECTION 6: FUNCTION — core_analytics__search_catalog_rich
-- Extracted VERBATIM from sql/schema/current-schema.sql.
-- Uses similarity() → requires pg_trgm (Section 1).
-- Uses mv_core_analytics__catalog_entities (Section 4 — now a VIEW).
-- Uses core_analytics__components_articles (Section 3).
-- ============================================================

CREATE OR REPLACE FUNCTION public.core_analytics__search_catalog_rich(
    term    text,
    limit_n integer DEFAULT 50
)
RETURNS TABLE(
    entity_type          text,
    entity_key           text,
    label                text,
    score                real,
    fascia               text,
    categoria            text,
    famiglia             text,
    fascia_prezzo        text,
    codart               text,
    articolo_nome        text,
    pot_size             text,
    prezzo_iva_inclusa   numeric
)
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


-- ============================================================
-- SECTION 7: FUNCTION — core_analytics__catalog_children
-- Extracted VERBATIM from sql/schema/current-schema.sql.
-- Uses core_analytics__components_articles (Section 3).
-- ============================================================

CREATE OR REPLACE FUNCTION public.core_analytics__catalog_children(
    p_level        text,
    p_fascia       text    DEFAULT NULL,
    p_categoria    text    DEFAULT NULL,
    p_famiglia     text    DEFAULT NULL,
    p_fascia_prezzo text   DEFAULT NULL,
    p_limit        integer DEFAULT 500
)
RETURNS TABLE(
    node_type text,
    node_key  text,
    label     text,
    extra     jsonb
)
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


-- ============================================================
-- SECTION 8: FUNCTION — core_analytics__list_catalog
-- Extracted VERBATIM from sql/schema/current-schema.sql.
-- Uses core_analytics__catalog (Section 5 — rewritten VIEW).
-- ============================================================

CREATE OR REPLACE FUNCTION public.core_analytics__list_catalog(
    p_entity_type text,
    p_limit       integer DEFAULT 500
)
RETURNS TABLE(
    entity_type text,
    entity_key  text,
    label       text
)
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


-- ============================================================
-- END OF WAVE 7B.2-A SCHEMA
-- Object counts:
--   Extensions: 1  (pg_trgm)
--   Tables:     1  (greenhouse_products_normalized)
--   Views:      3  (components_articles, mv_catalog_entities, catalog)
--   Functions:  3  (search_catalog_rich, catalog_children, list_catalog)
--   Total:      8
-- ============================================================
