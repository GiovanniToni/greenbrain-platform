
BEGIN;

TRUNCATE TABLE public.greenhouse_sales_family_daily_fact;
TRUNCATE TABLE public.greenhouse_series_list_fact;
TRUNCATE TABLE public.greenhouse_weather_daily;
TRUNCATE TABLE public.greenhouse_holidays;
TRUNCATE TABLE public.greenhouse_forecast_features_dense;
TRUNCATE TABLE public.greenhouse_sales_family_daily_dense;
TRUNCATE TABLE public.famiglie_catalog_static;

INSERT INTO public.famiglie_catalog_static (famiglia, famiglia_slug) VALUES
('rosa', 'rosa'),
('lavanda', 'lavanda'),
('ficus elastica', 'ficus-elastica');

INSERT INTO public.greenhouse_weather_daily (
    data, tmin_c, tmax_c, tavg_c, rain_mm, sun_hours
)
SELECT
    d::date,
    8 + (random()*10)::numeric(5,2),
    18 + (random()*12)::numeric(5,2),
    13 + (random()*10)::numeric(5,2),
    (random()*8)::numeric(5,2),
    4 + (random()*8)::numeric(5,2)
FROM generate_series(date '2025-01-01', date '2025-03-31', interval '1 day') d;

INSERT INTO public.greenhouse_holidays (data, is_holiday, holiday_name) VALUES
('2025-01-01', true, 'Capodanno'),
('2025-01-06', true, 'Epifania');

INSERT INTO public.greenhouse_sales_family_daily_fact (
    data, famiglia, fascia_prezzo_iva_inc,
    qty_venduta, imponibile_netto_tot, num_articoli,
    fascia_corretta, categoria_corretta,
    pot_sizes_text, pot_sizes_json,
    articoli_inclusi, articoli_json
)
SELECT
    d::date,
    fam.famiglia,
    fas.fascia,
    CASE
        WHEN extract(dow from d) IN (0,6) THEN (2 + random()*8)::numeric(12,3)
        ELSE (random()*4)::numeric(12,3)
    END,
    CASE
        WHEN extract(dow from d) IN (0,6) THEN (20 + random()*120)::numeric(12,2)
        ELSE (10 + random()*60)::numeric(12,2)
    END,
    1 + (random()*4)::int,
    CASE
        WHEN fam.famiglia in ('rosa','lavanda') THEN 'esterno'
        ELSE 'interno'
    END,
    CASE
        WHEN fam.famiglia in ('rosa','lavanda') THEN 'fiorite'
        ELSE 'verdi'
    END,
    '14,17',
    '["14","17"]'::jsonb,
    'demo-articolo',
    '[{"codart":"TEST001"}]'::jsonb
FROM generate_series(date '2025-01-01', date '2025-03-31', interval '1 day') d
CROSS JOIN (
    VALUES ('rosa'), ('lavanda'), ('ficus elastica')
) AS fam(famiglia)
CROSS JOIN (
    VALUES ('A'), ('B')
) AS fas(fascia)
WHERE random() > 0.15;

INSERT INTO public.greenhouse_series_list_fact (
    famiglia, fascia_prezzo_iva_inc, fascia_corretta, categoria_corretta
)
SELECT DISTINCT
    famiglia,
    fascia_prezzo_iva_inc,
    fascia_corretta,
    categoria_corretta
FROM public.greenhouse_sales_family_daily_fact
ON CONFLICT (famiglia, fascia_prezzo_iva_inc) DO NOTHING;

COMMIT;
