CREATE TABLE IF NOT EXISTS public.greenhouse_weekday_strength (
    famiglia text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    week_of_year integer NOT NULL,
    dow integer NOT NULL,
    strength numeric(10,4) NOT NULL DEFAULT 1.0,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT greenhouse_weekday_strength_pkey
        PRIMARY KEY (famiglia, fascia_prezzo_iva_inc, week_of_year, dow)
);

CREATE TABLE IF NOT EXISTS public.greenhouse_weekday_strength_family (
    famiglia text NOT NULL,
    week_of_year integer NOT NULL,
    dow integer NOT NULL,
    strength numeric(10,4) NOT NULL DEFAULT 1.0,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT greenhouse_weekday_strength_family_pkey
        PRIMARY KEY (famiglia, week_of_year, dow)
);

INSERT INTO public.greenhouse_weekday_strength (
    famiglia, fascia_prezzo_iva_inc, week_of_year, dow, strength
)
SELECT DISTINCT
    lower(trim(famiglia)) as famiglia,
    fascia_prezzo_iva_inc,
    COALESCE(week_num, extract(week from data)::int) as week_of_year,
    COALESCE(dow, extract(dow from data)::int) as dow,
    1.0 as strength
FROM public.greenhouse_forecast_features_dense
WHERE famiglia IS NOT NULL
  AND fascia_prezzo_iva_inc IS NOT NULL
  AND data IS NOT NULL
ON CONFLICT (famiglia, fascia_prezzo_iva_inc, week_of_year, dow)
DO NOTHING;

INSERT INTO public.greenhouse_weekday_strength_family (
    famiglia, week_of_year, dow, strength
)
SELECT DISTINCT
    lower(trim(famiglia)) as famiglia,
    COALESCE(week_num, extract(week from data)::int) as week_of_year,
    COALESCE(dow, extract(dow from data)::int) as dow,
    1.0 as strength
FROM public.greenhouse_forecast_features_dense
WHERE famiglia IS NOT NULL
  AND data IS NOT NULL
ON CONFLICT (famiglia, week_of_year, dow)
DO NOTHING;
