CREATE SCHEMA IF NOT EXISTS ml_forecast;

CREATE OR REPLACE VIEW ml_forecast.v_family_execution_routing_v2 AS
SELECT
    lower(trim(f.famiglia))::text AS family_name,
    'unknown'::text               AS demand_class_final,
    'ENGINE_NAIVE_ZERO'::text     AS model_code,
    'ENGINE_NAIVE_ZERO'::text     AS registry_execution_engine,
    'ENGINE_NAIVE_ZERO'::text     AS target_execution_engine,
    'ENGINE_NAIVE_ZERO'::text     AS current_execution_engine,
    'ENGINE_NAIVE_ZERO'::text     AS effective_execution_engine,
    'runtime_default'::text       AS routing_source,
    TRUE                          AS is_active
FROM public.v_famiglie_catalog f;
