-- Local ML runtime compatibility patch

REFRESH MATERIALIZED VIEW public.mv_famiglie_catalog;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'ml_forecast'
      AND table_name = 'v_family_execution_routing_v2'
      AND column_name = 'needs_initial_train'
  ) THEN
    IF NOT EXISTS (
      SELECT 1
      FROM information_schema.views
      WHERE table_schema = 'ml_forecast'
        AND table_name = 'v_family_execution_routing_v2_base_compat'
    ) THEN
      ALTER VIEW ml_forecast.v_family_execution_routing_v2
      RENAME TO v_family_execution_routing_v2_base_compat;
    END IF;

    CREATE VIEW ml_forecast.v_family_execution_routing_v2 AS
    SELECT
      b.*,
      true AS needs_initial_train,
      true AS needs_retrain,
      'v4'::text AS model_version,
      'local_runtime_default'::text AS routing_reason
    FROM ml_forecast.v_family_execution_routing_v2_base_compat b;
  END IF;
END $$;
