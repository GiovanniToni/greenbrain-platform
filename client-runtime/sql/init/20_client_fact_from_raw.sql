
BEGIN;

CREATE OR REPLACE FUNCTION public.refresh_fact_from_raw(
    p_from_date date,
    p_to_date date
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_from_date IS NULL OR p_to_date IS NULL THEN
        RAISE EXCEPTION 'p_from_date e p_to_date sono obbligatori';
    END IF;

    IF p_from_date > p_to_date THEN
        RAISE EXCEPTION 'p_from_date non può essere maggiore di p_to_date';
    END IF;

    DELETE FROM public.greenhouse_sales_family_daily_fact
    WHERE data BETWEEN p_from_date AND p_to_date;

    INSERT INTO public.greenhouse_sales_family_daily_fact (
        data,
        famiglia,
        fascia_prezzo_iva_inc,
        qty_venduta,
        imponibile_netto_tot,
        num_articoli,
        fascia_corretta,
        categoria_corretta,
        pot_sizes_text,
        pot_sizes_json,
        articoli_inclusi,
        articoli_json
    )
    SELECT
        r.data_movimento AS data,
        p.famiglia,
        p.fascia_prezzo_iva_inc,
        COALESCE(SUM(r.quantita), 0)::numeric(12,3) AS qty_venduta,
        COALESCE(SUM(r.imponibilenetto), 0)::numeric(14,2) AS imponibile_netto_tot,
        COUNT(DISTINCT r.codart)::int AS num_articoli,
        p.fascia_corretta,
        p.categoria_corretta,
        STRING_AGG(DISTINCT COALESCE(p.pot_size, ''), ',' ORDER BY COALESCE(p.pot_size, '')) AS pot_sizes_text,
        COALESCE(
            jsonb_agg(DISTINCT to_jsonb(p.pot_size)) FILTER (WHERE p.pot_size IS NOT NULL),
            '[]'::jsonb
        ) AS pot_sizes_json,
        STRING_AGG(DISTINCT r.codart, ',' ORDER BY r.codart) AS articoli_inclusi,
        COALESCE(
            jsonb_agg(
                DISTINCT jsonb_build_object('codart', r.codart)
            ) FILTER (WHERE r.codart IS NOT NULL),
            '[]'::jsonb
        ) AS articoli_json
    FROM public.greenhouse_sales_raw r
    JOIN public.greenhouse_products_normalized p
      ON p.codart = r.codart
    WHERE r.data_movimento BETWEEN p_from_date AND p_to_date
      AND COALESCE(r.movim_cassa, 0) = 1
      AND COALESCE(r.disattivato, 0) = 0
      AND COALESCE(p.is_active, true) = true
      AND COALESCE(p.is_classified, false) = true
      AND p.famiglia IS NOT NULL
      AND p.categoria_corretta IS NOT NULL
      AND p.fascia_corretta IS NOT NULL
      AND p.fascia_prezzo_iva_inc IS NOT NULL
    GROUP BY
        r.data_movimento,
        p.famiglia,
        p.fascia_prezzo_iva_inc,
        p.fascia_corretta,
        p.categoria_corretta
    ORDER BY
        r.data_movimento,
        p.famiglia,
        p.fascia_prezzo_iva_inc;
END;
$$;

COMMIT;
