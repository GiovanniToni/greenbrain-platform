-- GreenBrain weather foundation.
-- Additive-only migration.
-- Purpose:
-- - introduce normalized multi-location weather storage
-- - support Open-Meteo daily actuals, daily forecasts, current conditions
-- - prepare tenant/customer weather-location assignment for future local sync
-- - keep legacy public.greenhouse_weather_daily untouched

BEGIN;

CREATE SCHEMA IF NOT EXISTS gb_weather;

COMMENT ON SCHEMA gb_weather IS
  'Normalized weather data, forecasts, ingestion logs, and tenant/location mapping for GreenBrain.';

CREATE TABLE IF NOT EXISTS gb_weather.locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  location_code text NOT NULL,
  display_name text NOT NULL,
  municipality text,
  province_code text,
  region text,
  country_code text NOT NULL DEFAULT 'IT',
  latitude numeric(9,6) NOT NULL,
  longitude numeric(9,6) NOT NULL,
  timezone text NOT NULL DEFAULT 'Europe/Rome',
  is_active boolean NOT NULL DEFAULT true,
  is_default boolean NOT NULL DEFAULT false,
  source text NOT NULL DEFAULT 'manual_seed',
  source_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT gb_weather_locations_code_chk
    CHECK (location_code = lower(location_code) AND location_code ~ '^[a-z0-9][a-z0-9_-]*$'),
  CONSTRAINT gb_weather_locations_lat_chk
    CHECK (latitude >= -90 AND latitude <= 90),
  CONSTRAINT gb_weather_locations_lon_chk
    CHECK (longitude >= -180 AND longitude <= 180)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_gb_weather_locations_code
  ON gb_weather.locations (location_code);

CREATE INDEX IF NOT EXISTS idx_gb_weather_locations_active
  ON gb_weather.locations (is_active, location_code);

CREATE UNIQUE INDEX IF NOT EXISTS ux_gb_weather_locations_single_default
  ON gb_weather.locations (is_default)
  WHERE is_default = true;

COMMENT ON TABLE gb_weather.locations IS
  'Canonical weather locations used by GreenBrain for weather ingestion, ML features, frontend display, and future local sync.';

CREATE TABLE IF NOT EXISTS gb_weather.tenant_location_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_code text NOT NULL REFERENCES public.greenbrain_tenants(tenant_code) ON DELETE CASCADE,
  customer_id uuid REFERENCES public.gb_customer_companies(customer_id) ON DELETE SET NULL,
  location_id uuid NOT NULL REFERENCES gb_weather.locations(id) ON DELETE RESTRICT,
  assignment_type text NOT NULL DEFAULT 'primary',
  is_active boolean NOT NULL DEFAULT true,
  sync_to_local boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  notes text,
  CONSTRAINT gb_weather_tenant_location_assignment_type_chk
    CHECK (assignment_type IN ('primary', 'ml_default', 'sync_default', 'display', 'other'))
);

CREATE INDEX IF NOT EXISTS idx_gb_weather_tenant_location_tenant
  ON gb_weather.tenant_location_assignments (tenant_code, is_active);

CREATE INDEX IF NOT EXISTS idx_gb_weather_tenant_location_customer
  ON gb_weather.tenant_location_assignments (customer_id);

CREATE INDEX IF NOT EXISTS idx_gb_weather_tenant_location_location
  ON gb_weather.tenant_location_assignments (location_id);

CREATE UNIQUE INDEX IF NOT EXISTS ux_gb_weather_tenant_location_active_type
  ON gb_weather.tenant_location_assignments (tenant_code, assignment_type)
  WHERE is_active = true;

COMMENT ON TABLE gb_weather.tenant_location_assignments IS
  'Assigns a tenant/customer to one or more weather locations. Used later for ML default weather and cloud-to-local weather sync.';

CREATE TABLE IF NOT EXISTS gb_weather.daily_actuals (
  location_id uuid NOT NULL REFERENCES gb_weather.locations(id) ON DELETE CASCADE,
  weather_date date NOT NULL,
  provider text NOT NULL DEFAULT 'open_meteo',
  provider_model text,
  weather_code integer,

  temperature_2m_max_c numeric(6,2),
  temperature_2m_min_c numeric(6,2),
  temperature_2m_mean_c numeric(6,2),

  apparent_temperature_max_c numeric(6,2),
  apparent_temperature_min_c numeric(6,2),
  apparent_temperature_mean_c numeric(6,2),

  sunrise_local timestamp without time zone,
  sunset_local timestamp without time zone,
  daylight_duration_seconds integer,
  sunshine_duration_seconds integer,

  precipitation_sum_mm numeric(8,2),
  rain_sum_mm numeric(8,2),
  snowfall_sum_cm numeric(8,2),
  precipitation_hours numeric(6,2),

  wind_speed_10m_max_kmh numeric(7,2),
  wind_gusts_10m_max_kmh numeric(7,2),
  wind_direction_10m_dominant_deg integer,

  shortwave_radiation_sum_mj_m2 numeric(9,3),
  et0_fao_evapotranspiration_mm numeric(8,3),

  relative_humidity_2m_mean_pct numeric(6,2),
  relative_humidity_2m_max_pct numeric(6,2),
  relative_humidity_2m_min_pct numeric(6,2),
  dew_point_2m_mean_c numeric(6,2),
  cloud_cover_mean_pct numeric(6,2),
  soil_temperature_0_to_7cm_mean_c numeric(6,2),
  soil_moisture_0_to_7cm_mean_m3_m3 numeric(8,5),

  source_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  fetched_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (location_id, weather_date, provider)
);

CREATE INDEX IF NOT EXISTS idx_gb_weather_daily_actuals_location_date
  ON gb_weather.daily_actuals (location_id, weather_date DESC);

CREATE INDEX IF NOT EXISTS idx_gb_weather_daily_actuals_date
  ON gb_weather.daily_actuals (weather_date DESC);

COMMENT ON TABLE gb_weather.daily_actuals IS
  'Historical/recent daily weather actuals by location and provider. Open-Meteo historical archive is the initial provider.';

CREATE TABLE IF NOT EXISTS gb_weather.daily_forecasts (
  location_id uuid NOT NULL REFERENCES gb_weather.locations(id) ON DELETE CASCADE,
  forecast_run_date date NOT NULL,
  forecast_date date NOT NULL,
  provider text NOT NULL DEFAULT 'open_meteo',
  provider_model text,
  forecast_horizon_days integer NOT NULL,

  weather_code integer,

  temperature_2m_max_c numeric(6,2),
  temperature_2m_min_c numeric(6,2),
  temperature_2m_mean_c numeric(6,2),

  apparent_temperature_max_c numeric(6,2),
  apparent_temperature_min_c numeric(6,2),
  apparent_temperature_mean_c numeric(6,2),

  sunrise_local timestamp without time zone,
  sunset_local timestamp without time zone,
  daylight_duration_seconds integer,
  sunshine_duration_seconds integer,

  uv_index_max numeric(6,2),

  precipitation_sum_mm numeric(8,2),
  rain_sum_mm numeric(8,2),
  showers_sum_mm numeric(8,2),
  snowfall_sum_cm numeric(8,2),
  precipitation_probability_max_pct numeric(6,2),
  precipitation_hours numeric(6,2),

  wind_speed_10m_max_kmh numeric(7,2),
  wind_gusts_10m_max_kmh numeric(7,2),
  wind_direction_10m_dominant_deg integer,

  shortwave_radiation_sum_mj_m2 numeric(9,3),
  et0_fao_evapotranspiration_mm numeric(8,3),

  relative_humidity_2m_mean_pct numeric(6,2),
  cloud_cover_mean_pct numeric(6,2),

  source_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  fetched_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (location_id, forecast_run_date, forecast_date, provider),

  CONSTRAINT gb_weather_daily_forecasts_horizon_chk
    CHECK (forecast_horizon_days >= 0 AND forecast_horizon_days <= 30)
);

CREATE INDEX IF NOT EXISTS idx_gb_weather_daily_forecasts_location_run_date
  ON gb_weather.daily_forecasts (location_id, forecast_run_date DESC);

CREATE INDEX IF NOT EXISTS idx_gb_weather_daily_forecasts_location_forecast_date
  ON gb_weather.daily_forecasts (location_id, forecast_date DESC);

COMMENT ON TABLE gb_weather.daily_forecasts IS
  'Daily weather forecasts by location, forecast run date, forecast date, and provider. Initial horizon is 10 days.';

CREATE TABLE IF NOT EXISTS gb_weather.current_conditions (
  location_id uuid NOT NULL REFERENCES gb_weather.locations(id) ON DELETE CASCADE,
  provider text NOT NULL DEFAULT 'open_meteo',
  observed_at timestamptz,
  fetched_at timestamptz NOT NULL DEFAULT now(),

  temperature_2m_c numeric(6,2),
  relative_humidity_2m_pct numeric(6,2),
  apparent_temperature_c numeric(6,2),
  is_day boolean,
  precipitation_mm numeric(8,2),
  rain_mm numeric(8,2),
  showers_mm numeric(8,2),
  snowfall_cm numeric(8,2),
  weather_code integer,
  cloud_cover_pct numeric(6,2),
  wind_speed_10m_kmh numeric(7,2),
  wind_gusts_10m_kmh numeric(7,2),

  source_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (location_id, provider)
);

CREATE INDEX IF NOT EXISTS idx_gb_weather_current_conditions_location
  ON gb_weather.current_conditions (location_id, fetched_at DESC);

COMMENT ON TABLE gb_weather.current_conditions IS
  'Latest current weather conditions by location and provider.';

CREATE TABLE IF NOT EXISTS gb_weather.ingestion_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL DEFAULT 'open_meteo',
  run_type text NOT NULL,
  status text NOT NULL DEFAULT 'running',
  location_id uuid REFERENCES gb_weather.locations(id) ON DELETE SET NULL,
  date_from date,
  date_to date,
  forecast_days integer,
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  rows_requested integer NOT NULL DEFAULT 0,
  rows_upserted integer NOT NULL DEFAULT 0,
  rows_failed integer NOT NULL DEFAULT 0,
  source_params jsonb NOT NULL DEFAULT '{}'::jsonb,
  result_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT gb_weather_ingestion_runs_type_chk
    CHECK (run_type IN ('historical_backfill', 'recent_actuals', 'forecast', 'current', 'manual_test')),
  CONSTRAINT gb_weather_ingestion_runs_status_chk
    CHECK (status IN ('running', 'ok', 'partial', 'failed', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_gb_weather_ingestion_runs_started
  ON gb_weather.ingestion_runs (started_at DESC);

CREATE INDEX IF NOT EXISTS idx_gb_weather_ingestion_runs_location_started
  ON gb_weather.ingestion_runs (location_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_gb_weather_ingestion_runs_status
  ON gb_weather.ingestion_runs (status, started_at DESC);

COMMENT ON TABLE gb_weather.ingestion_runs IS
  'Audit log for weather ingestion/backfill/update runs.';

INSERT INTO gb_weather.locations (
  location_code,
  display_name,
  municipality,
  province_code,
  region,
  country_code,
  latitude,
  longitude,
  timezone,
  is_active,
  is_default,
  source,
  source_metadata,
  notes
)
VALUES
  (
    'pistoia',
    'Pistoia',
    'Pistoia',
    'PT',
    'Toscana',
    'IT',
    43.933334,
    10.916667,
    'Europe/Rome',
    true,
    true,
    'manual_seed',
    '{"coordinate_source":"latlong.net / web verification"}'::jsonb,
    'Default weather location for initial GreenBrain ML compatibility.'
  ),
  (
    'quarrata',
    'Quarrata',
    'Quarrata',
    'PT',
    'Toscana',
    'IT',
    43.848369,
    10.978881,
    'Europe/Rome',
    true,
    false,
    'manual_seed',
    '{"coordinate_source":"latitude.to / web verification"}'::jsonb,
    null
  ),
  (
    'prato',
    'Prato',
    'Prato',
    'PO',
    'Toscana',
    'IT',
    43.880001,
    11.098333,
    'Europe/Rome',
    true,
    false,
    'manual_seed',
    '{"coordinate_source":"latlong.net / web verification"}'::jsonb,
    null
  ),
  (
    'firenze',
    'Firenze',
    'Firenze',
    'FI',
    'Toscana',
    'IT',
    43.769562,
    11.255814,
    'Europe/Rome',
    true,
    false,
    'manual_seed',
    '{"coordinate_source":"latlong.net / web verification"}'::jsonb,
    null
  )
ON CONFLICT (location_code)
DO UPDATE SET
  display_name = EXCLUDED.display_name,
  municipality = EXCLUDED.municipality,
  province_code = EXCLUDED.province_code,
  region = EXCLUDED.region,
  country_code = EXCLUDED.country_code,
  latitude = EXCLUDED.latitude,
  longitude = EXCLUDED.longitude,
  timezone = EXCLUDED.timezone,
  is_active = EXCLUDED.is_active,
  is_default = EXCLUDED.is_default,
  source = EXCLUDED.source,
  source_metadata = EXCLUDED.source_metadata,
  notes = EXCLUDED.notes,
  updated_at = now();

CREATE OR REPLACE VIEW gb_weather.v_locations_active AS
SELECT
  id,
  location_code,
  display_name,
  municipality,
  province_code,
  region,
  country_code,
  latitude,
  longitude,
  timezone,
  is_default
FROM gb_weather.locations
WHERE is_active = true;

CREATE OR REPLACE VIEW gb_weather.v_legacy_weather_daily_default AS
SELECT
  a.weather_date AS data,
  a.temperature_2m_min_c AS tmin_c,
  a.temperature_2m_max_c AS tmax_c,
  a.temperature_2m_mean_c AS tavg_c,
  COALESCE(a.rain_sum_mm, a.precipitation_sum_mm) AS rain_mm,
  CASE
    WHEN a.sunshine_duration_seconds IS NULL THEN NULL
    ELSE round((a.sunshine_duration_seconds::numeric / 3600.0), 2)
  END AS sun_hours,
  a.fetched_at,
  l.location_code
FROM gb_weather.daily_actuals a
JOIN gb_weather.locations l
  ON l.id = a.location_id
WHERE l.is_default = true
  AND a.provider = 'open_meteo';

CREATE OR REPLACE VIEW gb_weather.v_latest_forecast_10d AS
WITH latest_run AS (
  SELECT
    location_id,
    provider,
    max(forecast_run_date) AS forecast_run_date
  FROM gb_weather.daily_forecasts
  GROUP BY location_id, provider
)
SELECT
  f.*
FROM gb_weather.daily_forecasts f
JOIN latest_run lr
  ON lr.location_id = f.location_id
 AND lr.provider = f.provider
 AND lr.forecast_run_date = f.forecast_run_date
WHERE f.forecast_horizon_days BETWEEN 0 AND 10;

COMMIT;
