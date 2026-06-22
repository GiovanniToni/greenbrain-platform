BEGIN;

CREATE OR REPLACE FUNCTION public.promote_source_import_sales_raw_to_greenhouse_raw(
    p_source_client_code text DEFAULT NULL
)
RETURNS TABLE(
    inserted_count bigint,
    updated_count bigint,
    source_rows bigint,
    target_rows bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_inserted bigint := 0;
    v_updated bigint := 0;
    v_source_rows bigint := 0;
    v_target_rows bigint := 0;
BEGIN
    IF to_regclass('source_import.sales_raw') IS NULL THEN
        RETURN QUERY SELECT 0::bigint, 0::bigint, 0::bigint, 0::bigint;
        RETURN;
    END IF;

    SELECT count(*)
      INTO v_source_rows
    FROM source_import.sales_raw s
    WHERE p_source_client_code IS NULL
       OR s.source_client_code = p_source_client_code;

    UPDATE public.greenhouse_sales_raw t
    SET
        codart = s.codart::varchar,
        descrizione = s.descrizione::varchar,
        tipo = s.tipo::varchar,
        fascia = s.fascia::varchar,
        categoria = s.categoria::varchar,
        quantita = s.quantita,
        imponibilenetto = s.imponibilenetto,
        data_movimento = s.data_movimento::date,
        disattivato = s.disattivato,
        movim_cassa = s.movim_cassa,
        load_timestamp = COALESCE(s.load_timestamp, now()::timestamp)
    FROM source_import.sales_raw s
    WHERE t.progressivo = s.progressivo
      AND (p_source_client_code IS NULL OR s.source_client_code = p_source_client_code);

    GET DIAGNOSTICS v_updated = ROW_COUNT;

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
        s.codart::varchar,
        s.descrizione::varchar,
        s.tipo::varchar,
        s.fascia::varchar,
        s.categoria::varchar,
        s.quantita,
        s.imponibilenetto,
        s.data_movimento::date,
        s.disattivato,
        s.movim_cassa,
        COALESCE(s.load_timestamp, now()::timestamp)
    FROM source_import.sales_raw s
    WHERE s.progressivo IS NOT NULL
      AND (p_source_client_code IS NULL OR s.source_client_code = p_source_client_code)
    ON CONFLICT (progressivo) DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    SELECT count(*)
      INTO v_target_rows
    FROM public.greenhouse_sales_raw;

    RETURN QUERY SELECT v_inserted, v_updated, v_source_rows, v_target_rows;
END;
$$;

COMMIT;
