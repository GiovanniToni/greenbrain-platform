
BEGIN;

-- =========================================================
-- ETL RUNS
-- =========================================================

CREATE TABLE IF NOT EXISTS public.etl_runs (
    run_id bigserial PRIMARY KEY,
    job_name text NOT NULL,
    run_type text NOT NULL,
    status text NOT NULL,
    started_at timestamptz NOT NULL DEFAULT now(),
    ended_at timestamptz,
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
    meta_json jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_etl_runs_job_started
    ON public.etl_runs (job_name, started_at desc);

CREATE INDEX IF NOT EXISTS idx_etl_runs_status
    ON public.etl_runs (status);

-- =========================================================
-- STAGING RAW
-- =========================================================

CREATE TABLE IF NOT EXISTS public.greenhouse_sales_raw_staging (
    progressivo bigint NOT NULL,
    codart varchar(50),
    descrizione varchar(255),
    tipo varchar(50),
    fascia varchar(50),
    categoria varchar(50),
    quantita numeric(10,2),
    imponibilenetto numeric(12,2),
    data_movimento date,
    disattivato smallint,
    movim_cassa smallint,
    load_timestamp timestamp without time zone DEFAULT now(),
    etl_run_id bigint,
    PRIMARY KEY (progressivo)
);

CREATE INDEX IF NOT EXISTS idx_sales_raw_staging_codart
    ON public.greenhouse_sales_raw_staging (codart);

CREATE INDEX IF NOT EXISTS idx_sales_raw_staging_data
    ON public.greenhouse_sales_raw_staging (data_movimento);

-- =========================================================
-- PRODUCTS NORMALIZED
-- =========================================================

CREATE TABLE IF NOT EXISTS public.greenhouse_products_normalized (
    codart varchar(50) PRIMARY KEY,
    descrizione_raw varchar(255),
    tipo varchar(50),

    famiglia text,
    categoria_corretta text,
    fascia_corretta text,
    fascia_prezzo_iva_inc text,

    pot_size text,
    brand text,
    varieta text,
    colore text,
    note_classificazione text,

    is_classified boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    classification_status text NOT NULL DEFAULT 'new',

    classified_by text,
    classified_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);


ALTER TABLE public.greenhouse_products_normalized
    ADD COLUMN IF NOT EXISTS descrizione_raw varchar(255),
    ADD COLUMN IF NOT EXISTS brand text,
    ADD COLUMN IF NOT EXISTS varieta text,
    ADD COLUMN IF NOT EXISTS colore text,
    ADD COLUMN IF NOT EXISTS note_classificazione text,
    ADD COLUMN IF NOT EXISTS is_classified boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS classification_status text NOT NULL DEFAULT 'new',
    ADD COLUMN IF NOT EXISTS classified_by text,
    ADD COLUMN IF NOT EXISTS classified_at timestamptz,
    ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

UPDATE public.greenhouse_products_normalized
SET descrizione_raw = COALESCE(descrizione_raw, descrizione)
WHERE descrizione_raw IS NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'greenhouse_products_normalized'
      AND column_name = 'is_classified'
  ) THEN
    EXECUTE '
      CREATE INDEX IF NOT EXISTS idx_products_normalized_is_classified
      ON public.greenhouse_products_normalized (is_classified)
    ';
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_products_normalized_famiglia
    ON public.greenhouse_products_normalized (famiglia);

-- =========================================================
-- TOUCH updated_at
-- =========================================================

CREATE OR REPLACE FUNCTION public.gb_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_products_normalized_touch ON public.greenhouse_products_normalized;

CREATE TRIGGER trg_products_normalized_touch
BEFORE UPDATE ON public.greenhouse_products_normalized
FOR EACH ROW
EXECUTE FUNCTION public.gb_touch_updated_at();

-- =========================================================
-- VIEW: articoli non classificati
-- =========================================================

CREATE OR REPLACE VIEW public.v_products_unclassified AS
SELECT
    r.codart,
    max(r.descrizione) as descrizione_raw,
    max(r.tipo) as tipo,
    min(r.data_movimento) as first_seen_date,
    max(r.data_movimento) as last_seen_date,
    count(*) as rows_n,
    sum(coalesce(r.quantita, 0))::numeric(14,2) as qty_tot
FROM public.greenhouse_sales_raw_staging r
LEFT JOIN public.greenhouse_products_normalized p
    ON p.codart = r.codart
WHERE coalesce(r.codart, '') <> ''
  AND (
      p.codart IS NULL
      OR coalesce(p.is_classified, false) = false
  )
GROUP BY r.codart;

COMMIT;
