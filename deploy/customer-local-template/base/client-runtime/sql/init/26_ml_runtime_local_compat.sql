-- Local ML runtime compatibility patch

REFRESH MATERIALIZED VIEW public.mv_famiglie_catalog;

CREATE OR REPLACE VIEW ml_forecast.v_family_execution_routing_v2 AS
SELECT
  lower(trim(famiglia)) AS family_name,
  lower(trim(famiglia)) AS family_slug,
  true AS is_active,
  true AS needs_initial_train,
  true AS needs_retrain,
  'v4'::text AS model_version,
  'NAIVE_ZERO'::text AS selected_model_code,
  'local_runtime_default'::text AS routing_reason
FROM public.mv_famiglie_catalog
WHERE famiglia IS NOT NULL
  AND trim(famiglia) <> '';
