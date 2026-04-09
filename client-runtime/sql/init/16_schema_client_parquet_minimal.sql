
BEGIN;

CREATE TABLE IF NOT EXISTS public.greenhouse_series_list_fact (
    famiglia text NOT NULL,
    fascia_prezzo_iva_inc text NOT NULL,
    fascia_corretta text,
    categoria_corretta text,
    CONSTRAINT greenhouse_series_list_fact_pkey
        PRIMARY KEY (famiglia, fascia_prezzo_iva_inc)
);

CREATE TABLE IF NOT EXISTS public.greenhouse_weather_daily (
    data date PRIMARY KEY,
    tmin_c numeric,
    tmax_c numeric,
    tavg_c numeric,
    rain_mm numeric,
    sun_hours numeric
);

CREATE TABLE IF NOT EXISTS public.greenhouse_holidays (
    data date PRIMARY KEY,
    is_holiday boolean NOT NULL DEFAULT true,
    holiday_name text
);

CREATE TABLE IF NOT EXISTS public.greenhouse_sales_family_daily_dense (
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

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'greenhouse_sales_family_daily_dense_pkey'
    ) THEN
        ALTER TABLE public.greenhouse_sales_family_daily_dense
        ADD CONSTRAINT greenhouse_sales_family_daily_dense_pkey
        PRIMARY KEY (data, famiglia, fascia_prezzo_iva_inc);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_dense_data
    ON public.greenhouse_sales_family_daily_dense (data);

CREATE INDEX IF NOT EXISTS idx_dense_series
    ON public.greenhouse_sales_family_daily_dense (famiglia, fascia_prezzo_iva_inc);

CREATE TABLE IF NOT EXISTS public.ops_parquet_export_runs (
    run_id bigint NOT NULL,
    dataset text NOT NULL,
    started_at timestamptz DEFAULT now() NOT NULL,
    ended_at timestamptz,
    status text DEFAULT 'running' NOT NULL,
    from_day date,
    to_day date,
    n_families integer,
    n_files integer,
    n_rows bigint,
    error_message text,
    meta jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS public.ops_parquet_export_runs_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.ops_parquet_export_runs_run_id_seq
    OWNED BY public.ops_parquet_export_runs.run_id;

ALTER TABLE public.ops_parquet_export_runs
    ALTER COLUMN run_id SET DEFAULT nextval('public.ops_parquet_export_runs_run_id_seq'::regclass);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'ops_parquet_export_runs_pkey'
    ) THEN
        ALTER TABLE public.ops_parquet_export_runs
        ADD CONSTRAINT ops_parquet_export_runs_pkey PRIMARY KEY (run_id);
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.ops_parquet_export_state (
    id integer DEFAULT 1 NOT NULL,
    dataset text NOT NULL,
    export_mode text NOT NULL,
    overwrite_days integer DEFAULT 40 NOT NULL,
    last_success_run_at timestamptz,
    last_success_day date,
    storage_prefix text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'ops_parquet_export_state_pkey'
    ) THEN
        ALTER TABLE public.ops_parquet_export_state
        ADD CONSTRAINT ops_parquet_export_state_pkey PRIMARY KEY (id);
    END IF;
END $$;

INSERT INTO public.ops_parquet_export_state (
    id, dataset, export_mode, overwrite_days, storage_prefix
)
VALUES (
    1, 'features_dense_ml_clean', 'full', 40, 'features_dense/v1'
)
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = '_touch_updated_at'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgname = 'trg_ops_parquet_export_state_touch'
    ) THEN
        CREATE TRIGGER trg_ops_parquet_export_state_touch
        BEFORE UPDATE ON public.ops_parquet_export_state
        FOR EACH ROW
        EXECUTE FUNCTION public._touch_updated_at();
    END IF;
END $$;

DROP VIEW IF EXISTS public.v_famiglie_catalog;
DROP MATERIALIZED VIEW IF EXISTS public.mv_famiglie_catalog;

CREATE MATERIALIZED VIEW public.mv_famiglie_catalog AS
SELECT DISTINCT
    lower(trim(both from famiglia)) AS famiglia,
    replace(lower(trim(both from famiglia)), ' ', '-') AS famiglia_slug
FROM public.greenhouse_forecast_features_dense
WITH NO DATA;

CREATE VIEW public.v_famiglie_catalog AS
SELECT
    famiglia,
    replace(lower(trim(both from famiglia)), ' ', '-') AS famiglia_slug
FROM public.mv_famiglie_catalog;

CREATE OR REPLACE FUNCTION public.refresh_dense_range_from_fact(p_start date, p_end date)
RETURNS void
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

CREATE OR REPLACE FUNCTION public.refresh_forecast_features_dense_range(p_start date, p_end date)
RETURNS void
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

COMMIT;
