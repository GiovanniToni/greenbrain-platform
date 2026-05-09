CREATE UNIQUE INDEX IF NOT EXISTS ux_greenhouse_forecast_features_dense_key
ON public.greenhouse_forecast_features_dense (
  data,
  famiglia,
  fascia_prezzo_iva_inc
);
