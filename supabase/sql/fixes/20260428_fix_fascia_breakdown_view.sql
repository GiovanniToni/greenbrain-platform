CREATE OR REPLACE VIEW public.core_analytics__breakdown_daily_fascia_fp_v2 AS
SELECT
  data,
  entity_key_lc,
  fascia_prezzo_iva_inc,
  qty_venduta::numeric(18,3) AS qty_venduta,
  imponibile_netto_tot::numeric(18,2) AS imponibile_netto_tot,
  num_articoli::integer AS num_articoli,
  qty_forecast::numeric(18,3) AS qty_forecast,
  dow::integer AS dow,
  is_holiday,
  holiday_name
FROM public.mv_core_analytics__breakdown_daily_fascia_fp;
