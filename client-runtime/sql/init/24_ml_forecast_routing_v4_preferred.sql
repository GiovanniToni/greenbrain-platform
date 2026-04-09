CREATE SCHEMA IF NOT EXISTS ml_forecast;

CREATE OR REPLACE VIEW ml_forecast.v_family_execution_routing_v2 AS
SELECT
    lower(trim(f.famiglia))::text AS family_name,
    'unknown'::text               AS demand_class_final,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM ml_ops.family_run_log_v1 fr
            WHERE lower(trim(fr.family_name)) = lower(trim(f.famiglia))
              AND fr.job_type = 'train_family'
              AND fr.status = 'success'
              AND fr.artifact_path IS NOT NULL
              AND fr.artifact_path LIKE '%_v4.pkl'
        )
        THEN 'V4_TWEEDIE_BUNDLE'
        ELSE 'ENGINE_NAIVE_ZERO'
    END::text AS model_code,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM ml_ops.family_run_log_v1 fr
            WHERE lower(trim(fr.family_name)) = lower(trim(f.famiglia))
              AND fr.job_type = 'train_family'
              AND fr.status = 'success'
              AND fr.artifact_path IS NOT NULL
              AND fr.artifact_path LIKE '%_v4.pkl'
        )
        THEN 'V4_TWEEDIE_BUNDLE'
        ELSE 'ENGINE_NAIVE_ZERO'
    END::text AS registry_execution_engine,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM ml_ops.family_run_log_v1 fr
            WHERE lower(trim(fr.family_name)) = lower(trim(f.famiglia))
              AND fr.job_type = 'train_family'
              AND fr.status = 'success'
              AND fr.artifact_path IS NOT NULL
              AND fr.artifact_path LIKE '%_v4.pkl'
        )
        THEN 'V4_TWEEDIE_BUNDLE'
        ELSE 'ENGINE_NAIVE_ZERO'
    END::text AS target_execution_engine,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM ml_ops.family_run_log_v1 fr
            WHERE lower(trim(fr.family_name)) = lower(trim(f.famiglia))
              AND fr.job_type = 'train_family'
              AND fr.status = 'success'
              AND fr.artifact_path IS NOT NULL
              AND fr.artifact_path LIKE '%_v4.pkl'
        )
        THEN 'V4_TWEEDIE_BUNDLE'
        ELSE 'ENGINE_NAIVE_ZERO'
    END::text AS current_execution_engine,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM ml_ops.family_run_log_v1 fr
            WHERE lower(trim(fr.family_name)) = lower(trim(f.famiglia))
              AND fr.job_type = 'train_family'
              AND fr.status = 'success'
              AND fr.artifact_path IS NOT NULL
              AND fr.artifact_path LIKE '%_v4.pkl'
        )
        THEN 'V4_TWEEDIE_BUNDLE'
        ELSE 'ENGINE_NAIVE_ZERO'
    END::text AS effective_execution_engine,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM ml_ops.family_run_log_v1 fr
            WHERE lower(trim(fr.family_name)) = lower(trim(f.famiglia))
              AND fr.job_type = 'train_family'
              AND fr.status = 'success'
              AND fr.artifact_path IS NOT NULL
              AND fr.artifact_path LIKE '%_v4.pkl'
        )
        THEN 'trained_v4_bundle'
        ELSE 'runtime_default'
    END::text AS routing_source,
    TRUE AS is_active
FROM public.v_famiglie_catalog f;
