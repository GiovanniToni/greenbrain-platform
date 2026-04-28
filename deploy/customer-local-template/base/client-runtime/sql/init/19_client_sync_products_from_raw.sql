
BEGIN;

CREATE OR REPLACE FUNCTION public.sync_products_normalized_from_raw()
RETURNS TABLE(inserted_count bigint, updated_count bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    v_before bigint := 0;
    v_after bigint := 0;
    v_inserted bigint := 0;
    v_updated bigint := 0;
BEGIN
    SELECT count(*) INTO v_before
    FROM public.greenhouse_products_normalized;

    WITH src AS (
        SELECT
            r.codart,
            max(r.descrizione) AS descrizione,
            max(r.descrizione) AS descrizione_raw,
            max(r.tipo) AS tipo,
            max(r.categoria) AS categoria,
            max(r.fascia) AS fascia
        FROM public.greenhouse_sales_raw r
        WHERE coalesce(r.codart, '') <> ''
        GROUP BY r.codart
    ),
    upd AS (
        UPDATE public.greenhouse_products_normalized p
        SET
            descrizione = s.descrizione,
            descrizione_raw = s.descrizione_raw,
            tipo = s.tipo,
            categoria = s.categoria,
            fascia = s.fascia,
            updated_at = now()
        FROM src s
        WHERE p.codart = s.codart
        RETURNING p.codart
    ),
    ins AS (
        INSERT INTO public.greenhouse_products_normalized (
            codart,
            descrizione,
            descrizione_raw,
            tipo,
            categoria,
            fascia,
            is_classified,
            is_active,
            classification_status,
            created_at,
            updated_at
        )
        SELECT
            s.codart,
            s.descrizione,
            s.descrizione_raw,
            s.tipo,
            s.categoria,
            s.fascia,
            false,
            true,
            'new',
            now(),
            now()
        FROM src s
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.greenhouse_products_normalized p
            WHERE p.codart = s.codart
        )
        RETURNING codart
    )
    SELECT
        (SELECT count(*) FROM ins),
        (SELECT count(*) FROM upd)
    INTO v_inserted, v_updated;

    SELECT count(*) INTO v_after
    FROM public.greenhouse_products_normalized;

    RETURN QUERY
    SELECT v_inserted, v_updated;
END;
$$;

COMMIT;
