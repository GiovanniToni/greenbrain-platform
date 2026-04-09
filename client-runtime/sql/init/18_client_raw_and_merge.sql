
BEGIN;

-- =========================================================
-- RAW TABLE
-- =========================================================

CREATE TABLE IF NOT EXISTS public.greenhouse_sales_raw (
  progressivo bigint NOT NULL,
  codart varchar(50),
  descrizione varchar(255),
  tipo varchar(50),
  fascia varchar(50),
  categoria varchar(50),
  quantita numeric(10, 2),
  imponibilenetto numeric(12, 2),
  data_movimento date,
  disattivato smallint,
  movim_cassa smallint,
  load_timestamp timestamp without time zone DEFAULT now(),
  CONSTRAINT greenhouse_sales_raw_pkey PRIMARY KEY (progressivo)
);

CREATE INDEX IF NOT EXISTS idx_sales_raw_codart
  ON public.greenhouse_sales_raw (codart);

CREATE INDEX IF NOT EXISTS idx_sales_raw_data
  ON public.greenhouse_sales_raw (data_movimento);

CREATE INDEX IF NOT EXISTS idx_sales_raw_data_codart_1prefix
  ON public.greenhouse_sales_raw (data_movimento)
  WHERE codart LIKE '1%';

-- =========================================================
-- STAGING -> RAW MERGE FUNCTION
-- =========================================================

CREATE OR REPLACE FUNCTION public.merge_greenhouse_sales_raw_from_staging()
RETURNS TABLE(inserted_count bigint, updated_count bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    v_inserted bigint := 0;
    v_updated bigint := 0;
BEGIN
    -- update existing
    UPDATE public.greenhouse_sales_raw t
    SET
        codart = s.codart,
        descrizione = s.descrizione,
        tipo = s.tipo,
        fascia = s.fascia,
        categoria = s.categoria,
        quantita = s.quantita,
        imponibilenetto = s.imponibilenetto,
        data_movimento = s.data_movimento,
        disattivato = s.disattivato,
        movim_cassa = s.movim_cassa,
        load_timestamp = COALESCE(s.load_timestamp, now())
    FROM public.greenhouse_sales_raw_staging s
    WHERE t.progressivo = s.progressivo;

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    -- insert new
    INSERT INTO public.greenhouse_sales_raw (
        progressivo,
        codart,
        descrizione,
        tipo,
        fascia,
        categoria,
        quantita,
        imponibilenetto,
        data_movimento,
        disattivato,
        movim_cassa,
        load_timestamp
    )
    SELECT
        s.progressivo,
        s.codart,
        s.descrizione,
        s.tipo,
        s.fascia,
        s.categoria,
        s.quantita,
        s.imponibilenetto,
        s.data_movimento,
        s.disattivato,
        s.movim_cassa,
        COALESCE(s.load_timestamp, now())
    FROM public.greenhouse_sales_raw_staging s
    LEFT JOIN public.greenhouse_sales_raw t
      ON t.progressivo = s.progressivo
    WHERE t.progressivo IS NULL;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    RETURN QUERY
    SELECT v_inserted, v_updated;
END;
$$;

COMMIT;
