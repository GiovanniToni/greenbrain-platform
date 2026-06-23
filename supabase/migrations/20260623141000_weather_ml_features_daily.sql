-- Weather ML daily feature store.
-- Purpose:
-- - keep gb_weather as normalized source data
-- - project multi-location weather into one daily ML feature row
-- - avoid rewriting public.greenhouse_forecast_features_dense immediately
-- - support enriched ML views and future vNext train/predict/export

CREATE TABLE IF NOT EXISTS public.greenhouse_weather_ml_features_daily (
  data date PRIMARY KEY,

  source_kind text NOT NULL CHECK (source_kind IN ('actual', 'forecast', 'mixed')),
  location_count integer NOT NULL DEFAULT 0,
  location_codes text,

  has_pistoia boolean NOT NULL DEFAULT false,
  has_firenze boolean NOT NULL DEFAULT false,
  has_prato boolean NOT NULL DEFAULT false,
  has_quarrata boolean NOT NULL DEFAULT false,

  area_avg_tmin_c numeric,
  area_avg_tmax_c numeric,
  area_avg_tavg_c numeric,
  area_min_tmin_c numeric,
  area_max_tmax_c numeric,
  area_temp_range_c numeric,
  area_avg_apparent_tavg_c numeric,

  area_avg_rain_mm numeric,
  area_max_rain_mm numeric,
  area_rainy_locations integer,
  area_heavy_rain_locations integer,

  area_avg_sun_hours numeric,
  area_max_sun_hours numeric,
  area_avg_shortwave_mj_m2 numeric,
  area_avg_et0_mm numeric,
  area_avg_humidity_pct numeric,
  area_avg_cloud_cover_pct numeric,
  area_avg_wind_max_kmh numeric,
  area_max_wind_gust_kmh numeric,

  area_avg_soil_temp_c numeric,
  area_avg_soil_moisture numeric,

  pistoia_tmin_c numeric,
  pistoia_tmax_c numeric,
  pistoia_tavg_c numeric,
  pistoia_apparent_tavg_c numeric,
  pistoia_rain_mm numeric,
  pistoia_sun_hours numeric,
  pistoia_et0_mm numeric,
  pistoia_humidity_pct numeric,
  pistoia_cloud_cover_pct numeric,
  pistoia_wind_max_kmh numeric,
  pistoia_soil_temp_c numeric,
  pistoia_soil_moisture numeric,

  is_rainy_day integer,
  is_heavy_rain_day integer,
  is_very_heavy_rain_day integer,
  is_dry_day integer,
  is_sunny_day integer,
  is_cloudy_day integer,
  is_hot_day integer,
  is_very_hot_day integer,
  is_cold_day integer,
  is_frost_risk_day integer,

  rain_3d_mm numeric,
  rain_7d_mm numeric,
  rain_14d_mm numeric,

  sun_hours_3d numeric,
  sun_hours_7d numeric,

  tavg_3d numeric,
  tavg_7d numeric,

  hot_days_7d integer,
  rainy_days_7d integer,
  dry_days_7d integer,

  garden_workability_score numeric(6,2),
  garden_visit_score numeric(6,2),
  planting_window_score numeric(6,2),
  heat_stress_score numeric(6,2),
  dryness_stress_score numeric(6,2),
  rain_disruption_score numeric(6,2),

  score_version text NOT NULL DEFAULT 'v3_20260623',

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_greenhouse_weather_ml_features_daily_source_kind
  ON public.greenhouse_weather_ml_features_daily(source_kind);

CREATE OR REPLACE FUNCTION public.refresh_greenhouse_weather_ml_features_daily(
  p_from date,
  p_to date
)
RETURNS TABLE(rows_upserted integer, from_date date, to_date date)
LANGUAGE plpgsql
AS $function$
DECLARE
  v_lb date;
  v_rows integer := 0;
BEGIN
  IF p_from IS NULL OR p_to IS NULL OR p_from > p_to THEN
    RAISE EXCEPTION USING MESSAGE =
      'range non valido: ' || COALESCE(p_from::text, 'null') || ' - ' || COALESCE(p_to::text, 'null');
  END IF;

  -- Lookback for 14d windows.
  v_lb := (p_from - interval '13 days')::date;

  PERFORM set_config('statement_timeout', '600000', true);

  WITH actuals AS (
    SELECT
      l.location_code,
      a.weather_date AS data,
      'actual'::text AS source_kind,
      a.weather_code,
      a.temperature_2m_min_c AS tmin_c,
      a.temperature_2m_max_c AS tmax_c,
      a.temperature_2m_mean_c AS tavg_c,
      a.apparent_temperature_mean_c AS apparent_tavg_c,
      COALESCE(a.rain_sum_mm, a.precipitation_sum_mm) AS rain_mm,
      a.precipitation_sum_mm,
      a.precipitation_hours,
      CASE
        WHEN a.sunshine_duration_seconds IS NULL THEN NULL
        ELSE round((a.sunshine_duration_seconds / 3600.0)::numeric, 2)
      END AS sun_hours,
      a.shortwave_radiation_sum_mj_m2,
      a.et0_fao_evapotranspiration_mm,
      a.relative_humidity_2m_mean_pct,
      a.cloud_cover_mean_pct,
      a.wind_speed_10m_max_kmh,
      a.wind_gusts_10m_max_kmh,
      a.soil_temperature_0_to_7cm_mean_c,
      a.soil_moisture_0_to_7cm_mean_m3_m3,
      a.fetched_at
    FROM gb_weather.daily_actuals a
    JOIN gb_weather.locations l ON l.id = a.location_id
    WHERE a.weather_date BETWEEN v_lb AND p_to
      AND l.is_active = true
  ),
  forecasts_latest AS (
    SELECT DISTINCT ON (l.location_code, f.forecast_date)
      l.location_code,
      f.forecast_date AS data,
      'forecast'::text AS source_kind,
      f.weather_code,
      f.temperature_2m_min_c AS tmin_c,
      f.temperature_2m_max_c AS tmax_c,
      f.temperature_2m_mean_c AS tavg_c,
      f.apparent_temperature_mean_c AS apparent_tavg_c,
      COALESCE(f.rain_sum_mm, f.precipitation_sum_mm) AS rain_mm,
      f.precipitation_sum_mm,
      f.precipitation_hours,
      CASE
        WHEN f.sunshine_duration_seconds IS NULL THEN NULL
        ELSE round((f.sunshine_duration_seconds / 3600.0)::numeric, 2)
      END AS sun_hours,
      f.shortwave_radiation_sum_mj_m2,
      f.et0_fao_evapotranspiration_mm,
      f.relative_humidity_2m_mean_pct,
      f.cloud_cover_mean_pct,
      f.wind_speed_10m_max_kmh,
      f.wind_gusts_10m_max_kmh,
      NULL::numeric AS soil_temperature_0_to_7cm_mean_c,
      NULL::numeric AS soil_moisture_0_to_7cm_mean_m3_m3,
      f.fetched_at
    FROM gb_weather.daily_forecasts f
    JOIN gb_weather.locations l ON l.id = f.location_id
    WHERE f.forecast_date BETWEEN v_lb AND p_to
      AND l.is_active = true
    ORDER BY l.location_code, f.forecast_date, f.forecast_run_date DESC, f.fetched_at DESC
  ),
  weather_source AS (
    SELECT * FROM actuals
    UNION ALL
    SELECT fl.*
    FROM forecasts_latest fl
    WHERE NOT EXISTS (
      SELECT 1
      FROM actuals a
      WHERE a.location_code = fl.location_code
        AND a.data = fl.data
    )
  ),
  daily_area AS (
    SELECT
      data,
      CASE
        WHEN count(*) FILTER (WHERE source_kind = 'actual') > 0
         AND count(*) FILTER (WHERE source_kind = 'forecast') > 0
        THEN 'mixed'
        WHEN count(*) FILTER (WHERE source_kind = 'actual') > 0
        THEN 'actual'
        ELSE 'forecast'
      END AS source_kind,

      count(*)::integer AS location_count,
      string_agg(location_code, ',' ORDER BY location_code) AS location_codes,

      bool_or(location_code = 'pistoia') AS has_pistoia,
      bool_or(location_code = 'firenze') AS has_firenze,
      bool_or(location_code = 'prato') AS has_prato,
      bool_or(location_code = 'quarrata') AS has_quarrata,

      round(avg(tmin_c), 3) AS area_avg_tmin_c,
      round(avg(tmax_c), 3) AS area_avg_tmax_c,
      round(avg(tavg_c), 3) AS area_avg_tavg_c,
      round(min(tmin_c), 3) AS area_min_tmin_c,
      round(max(tmax_c), 3) AS area_max_tmax_c,
      round(max(tmax_c) - min(tmin_c), 3) AS area_temp_range_c,
      round(avg(apparent_tavg_c), 3) AS area_avg_apparent_tavg_c,

      round(avg(rain_mm), 3) AS area_avg_rain_mm,
      round(max(rain_mm), 3) AS area_max_rain_mm,
      sum(CASE WHEN COALESCE(rain_mm, 0) > 0 THEN 1 ELSE 0 END)::integer AS area_rainy_locations,
      sum(CASE WHEN COALESCE(rain_mm, 0) >= 10 THEN 1 ELSE 0 END)::integer AS area_heavy_rain_locations,

      round(avg(sun_hours), 3) AS area_avg_sun_hours,
      round(max(sun_hours), 3) AS area_max_sun_hours,
      round(avg(shortwave_radiation_sum_mj_m2), 3) AS area_avg_shortwave_mj_m2,
      round(avg(et0_fao_evapotranspiration_mm), 3) AS area_avg_et0_mm,
      round(avg(relative_humidity_2m_mean_pct), 3) AS area_avg_humidity_pct,
      round(avg(cloud_cover_mean_pct), 3) AS area_avg_cloud_cover_pct,
      round(avg(wind_speed_10m_max_kmh), 3) AS area_avg_wind_max_kmh,
      round(max(wind_gusts_10m_max_kmh), 3) AS area_max_wind_gust_kmh,

      round(avg(soil_temperature_0_to_7cm_mean_c), 3) AS area_avg_soil_temp_c,
      round(avg(soil_moisture_0_to_7cm_mean_m3_m3), 3) AS area_avg_soil_moisture
    FROM weather_source
    GROUP BY data
  ),
  pistoia AS (
    SELECT
      data,
      tmin_c AS pistoia_tmin_c,
      tmax_c AS pistoia_tmax_c,
      tavg_c AS pistoia_tavg_c,
      apparent_tavg_c AS pistoia_apparent_tavg_c,
      rain_mm AS pistoia_rain_mm,
      sun_hours AS pistoia_sun_hours,
      et0_fao_evapotranspiration_mm AS pistoia_et0_mm,
      relative_humidity_2m_mean_pct AS pistoia_humidity_pct,
      cloud_cover_mean_pct AS pistoia_cloud_cover_pct,
      wind_speed_10m_max_kmh AS pistoia_wind_max_kmh,
      soil_temperature_0_to_7cm_mean_c AS pistoia_soil_temp_c,
      soil_moisture_0_to_7cm_mean_m3_m3 AS pistoia_soil_moisture
    FROM weather_source
    WHERE location_code = 'pistoia'
  ),
  features_base AS (
    SELECT
      d.*,
      p.pistoia_tmin_c,
      p.pistoia_tmax_c,
      p.pistoia_tavg_c,
      p.pistoia_apparent_tavg_c,
      p.pistoia_rain_mm,
      p.pistoia_sun_hours,
      p.pistoia_et0_mm,
      p.pistoia_humidity_pct,
      p.pistoia_cloud_cover_pct,
      p.pistoia_wind_max_kmh,
      p.pistoia_soil_temp_c,
      p.pistoia_soil_moisture,

      CASE WHEN COALESCE(d.area_avg_rain_mm, 0) > 0 THEN 1 ELSE 0 END AS is_rainy_day,
      CASE WHEN COALESCE(d.area_max_rain_mm, 0) >= 10 THEN 1 ELSE 0 END AS is_heavy_rain_day,
      CASE WHEN COALESCE(d.area_max_rain_mm, 0) >= 25 THEN 1 ELSE 0 END AS is_very_heavy_rain_day,
      CASE WHEN COALESCE(d.area_avg_rain_mm, 0) = 0 THEN 1 ELSE 0 END AS is_dry_day,
      CASE WHEN COALESCE(d.area_avg_sun_hours, 0) >= 8 THEN 1 ELSE 0 END AS is_sunny_day,
      CASE WHEN COALESCE(d.area_avg_cloud_cover_pct, 0) >= 70 THEN 1 ELSE 0 END AS is_cloudy_day,
      CASE WHEN COALESCE(d.area_max_tmax_c, 0) >= 30 THEN 1 ELSE 0 END AS is_hot_day,
      CASE WHEN COALESCE(d.area_max_tmax_c, 0) >= 35 THEN 1 ELSE 0 END AS is_very_hot_day,
      CASE WHEN COALESCE(d.area_min_tmin_c, 999) <= 5 THEN 1 ELSE 0 END AS is_cold_day,
      CASE WHEN COALESCE(d.area_min_tmin_c, 999) <= 0 THEN 1 ELSE 0 END AS is_frost_risk_day
    FROM daily_area d
    LEFT JOIN pistoia p USING(data)
  ),
  features_with_windows AS (
    SELECT
      f.*,

      round(sum(area_avg_rain_mm) OVER (ORDER BY data ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 3) AS rain_3d_mm,
      round(sum(area_avg_rain_mm) OVER (ORDER BY data ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 3) AS rain_7d_mm,
      round(sum(area_avg_rain_mm) OVER (ORDER BY data ROWS BETWEEN 13 PRECEDING AND CURRENT ROW), 3) AS rain_14d_mm,

      round(avg(area_avg_sun_hours) OVER (ORDER BY data ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 3) AS sun_hours_3d,
      round(avg(area_avg_sun_hours) OVER (ORDER BY data ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 3) AS sun_hours_7d,

      round(avg(area_avg_tavg_c) OVER (ORDER BY data ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 3) AS tavg_3d,
      round(avg(area_avg_tavg_c) OVER (ORDER BY data ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 3) AS tavg_7d,

      sum(is_hot_day) OVER (ORDER BY data ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)::integer AS hot_days_7d,
      sum(is_rainy_day) OVER (ORDER BY data ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)::integer AS rainy_days_7d,
      sum(is_dry_day) OVER (ORDER BY data ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)::integer AS dry_days_7d
    FROM features_base f
  ),
  features_with_scores AS (
    SELECT
      w.*,

      greatest(0, least(100,
        100
        - COALESCE(area_avg_rain_mm, 0) * 8
        - COALESCE(area_rainy_locations, 0) * 4
        - greatest(COALESCE(area_max_tmax_c, 0) - 28, 0) * 5
        - greatest(COALESCE(area_max_tmax_c, 0) - 34, 0) * 6
        - greatest(6 - COALESCE(area_min_tmin_c, 6), 0) * 4
        - greatest(COALESCE(area_avg_wind_max_kmh, 0) - 25, 0) * 1.5
        + least(COALESCE(area_avg_sun_hours, 0), 8) * 1.2
      ))::numeric(6,2) AS garden_workability_score,

      greatest(0, least(100,
        55
        + least(COALESCE(area_avg_sun_hours, 0), 10) * 2.5
        - COALESCE(area_avg_rain_mm, 0) * 8
        - COALESCE(area_rainy_locations, 0) * 3
        - greatest(COALESCE(area_max_tmax_c, 0) - 32, 0) * 6
        - greatest(COALESCE(area_avg_cloud_cover_pct, 0) - 65, 0) * 0.25
      ))::numeric(6,2) AS garden_visit_score,

      greatest(0, least(100,
        100
        - abs(COALESCE(area_avg_tavg_c, 18) - 18) * 5
        - greatest(COALESCE(area_max_tmax_c, 0) - 30, 0) * 5
        - COALESCE(area_max_rain_mm, 0) * 4
        + least(greatest(COALESCE(rain_7d_mm, 0), 0), 18) * 0.8
        - greatest(COALESCE(rain_7d_mm, 0) - 35, 0) * 2
      ))::numeric(6,2) AS planting_window_score,

      greatest(0,
        greatest(COALESCE(area_max_tmax_c, 0) - 28, 0) * 1.5
        + COALESCE(hot_days_7d, 0) * 1.2
        + greatest(COALESCE(area_avg_apparent_tavg_c, area_avg_tavg_c, 0) - 28, 0) * 1.2
      )::numeric(6,2) AS heat_stress_score,

      greatest(0,
        greatest(12 - COALESCE(rain_7d_mm, 0), 0) * 0.8
        + COALESCE(dry_days_7d, 0) * 0.8
        + COALESCE(area_avg_et0_mm, 0) * 0.8
        + greatest(COALESCE(area_max_tmax_c, 0) - 30, 0) * 0.7
      )::numeric(6,2) AS dryness_stress_score,

      least(100,
        greatest(0,
          COALESCE(area_max_rain_mm, 0) * 1.5
          + COALESCE(area_rainy_locations, 0) * 2
          + CASE WHEN COALESCE(area_max_rain_mm, 0) >= 10 THEN 10 ELSE 0 END
        )
      )::numeric(6,2) AS rain_disruption_score
    FROM features_with_windows w
  ),
  upserted AS (
    INSERT INTO public.greenhouse_weather_ml_features_daily (
      data,
      source_kind, location_count, location_codes,
      has_pistoia, has_firenze, has_prato, has_quarrata,
      area_avg_tmin_c, area_avg_tmax_c, area_avg_tavg_c, area_min_tmin_c, area_max_tmax_c,
      area_temp_range_c, area_avg_apparent_tavg_c,
      area_avg_rain_mm, area_max_rain_mm, area_rainy_locations, area_heavy_rain_locations,
      area_avg_sun_hours, area_max_sun_hours, area_avg_shortwave_mj_m2, area_avg_et0_mm,
      area_avg_humidity_pct, area_avg_cloud_cover_pct, area_avg_wind_max_kmh, area_max_wind_gust_kmh,
      area_avg_soil_temp_c, area_avg_soil_moisture,
      pistoia_tmin_c, pistoia_tmax_c, pistoia_tavg_c, pistoia_apparent_tavg_c, pistoia_rain_mm,
      pistoia_sun_hours, pistoia_et0_mm, pistoia_humidity_pct, pistoia_cloud_cover_pct,
      pistoia_wind_max_kmh, pistoia_soil_temp_c, pistoia_soil_moisture,
      is_rainy_day, is_heavy_rain_day, is_very_heavy_rain_day, is_dry_day, is_sunny_day,
      is_cloudy_day, is_hot_day, is_very_hot_day, is_cold_day, is_frost_risk_day,
      rain_3d_mm, rain_7d_mm, rain_14d_mm,
      sun_hours_3d, sun_hours_7d, tavg_3d, tavg_7d,
      hot_days_7d, rainy_days_7d, dry_days_7d,
      garden_workability_score, garden_visit_score, planting_window_score,
      heat_stress_score, dryness_stress_score, rain_disruption_score,
      score_version, created_at, updated_at
    )
    SELECT
      data,
      source_kind, location_count, location_codes,
      has_pistoia, has_firenze, has_prato, has_quarrata,
      area_avg_tmin_c, area_avg_tmax_c, area_avg_tavg_c, area_min_tmin_c, area_max_tmax_c,
      area_temp_range_c, area_avg_apparent_tavg_c,
      area_avg_rain_mm, area_max_rain_mm, area_rainy_locations, area_heavy_rain_locations,
      area_avg_sun_hours, area_max_sun_hours, area_avg_shortwave_mj_m2, area_avg_et0_mm,
      area_avg_humidity_pct, area_avg_cloud_cover_pct, area_avg_wind_max_kmh, area_max_wind_gust_kmh,
      area_avg_soil_temp_c, area_avg_soil_moisture,
      pistoia_tmin_c, pistoia_tmax_c, pistoia_tavg_c, pistoia_apparent_tavg_c, pistoia_rain_mm,
      pistoia_sun_hours, pistoia_et0_mm, pistoia_humidity_pct, pistoia_cloud_cover_pct,
      pistoia_wind_max_kmh, pistoia_soil_temp_c, pistoia_soil_moisture,
      is_rainy_day, is_heavy_rain_day, is_very_heavy_rain_day, is_dry_day, is_sunny_day,
      is_cloudy_day, is_hot_day, is_very_hot_day, is_cold_day, is_frost_risk_day,
      rain_3d_mm, rain_7d_mm, rain_14d_mm,
      sun_hours_3d, sun_hours_7d, tavg_3d, tavg_7d,
      hot_days_7d, rainy_days_7d, dry_days_7d,
      garden_workability_score, garden_visit_score, planting_window_score,
      heat_stress_score, dryness_stress_score, rain_disruption_score,
      'v3_20260623', now(), now()
    FROM features_with_scores
    WHERE data BETWEEN p_from AND p_to
    ON CONFLICT (data) DO UPDATE SET
      source_kind = EXCLUDED.source_kind,
      location_count = EXCLUDED.location_count,
      location_codes = EXCLUDED.location_codes,
      has_pistoia = EXCLUDED.has_pistoia,
      has_firenze = EXCLUDED.has_firenze,
      has_prato = EXCLUDED.has_prato,
      has_quarrata = EXCLUDED.has_quarrata,
      area_avg_tmin_c = EXCLUDED.area_avg_tmin_c,
      area_avg_tmax_c = EXCLUDED.area_avg_tmax_c,
      area_avg_tavg_c = EXCLUDED.area_avg_tavg_c,
      area_min_tmin_c = EXCLUDED.area_min_tmin_c,
      area_max_tmax_c = EXCLUDED.area_max_tmax_c,
      area_temp_range_c = EXCLUDED.area_temp_range_c,
      area_avg_apparent_tavg_c = EXCLUDED.area_avg_apparent_tavg_c,
      area_avg_rain_mm = EXCLUDED.area_avg_rain_mm,
      area_max_rain_mm = EXCLUDED.area_max_rain_mm,
      area_rainy_locations = EXCLUDED.area_rainy_locations,
      area_heavy_rain_locations = EXCLUDED.area_heavy_rain_locations,
      area_avg_sun_hours = EXCLUDED.area_avg_sun_hours,
      area_max_sun_hours = EXCLUDED.area_max_sun_hours,
      area_avg_shortwave_mj_m2 = EXCLUDED.area_avg_shortwave_mj_m2,
      area_avg_et0_mm = EXCLUDED.area_avg_et0_mm,
      area_avg_humidity_pct = EXCLUDED.area_avg_humidity_pct,
      area_avg_cloud_cover_pct = EXCLUDED.area_avg_cloud_cover_pct,
      area_avg_wind_max_kmh = EXCLUDED.area_avg_wind_max_kmh,
      area_max_wind_gust_kmh = EXCLUDED.area_max_wind_gust_kmh,
      area_avg_soil_temp_c = EXCLUDED.area_avg_soil_temp_c,
      area_avg_soil_moisture = EXCLUDED.area_avg_soil_moisture,
      pistoia_tmin_c = EXCLUDED.pistoia_tmin_c,
      pistoia_tmax_c = EXCLUDED.pistoia_tmax_c,
      pistoia_tavg_c = EXCLUDED.pistoia_tavg_c,
      pistoia_apparent_tavg_c = EXCLUDED.pistoia_apparent_tavg_c,
      pistoia_rain_mm = EXCLUDED.pistoia_rain_mm,
      pistoia_sun_hours = EXCLUDED.pistoia_sun_hours,
      pistoia_et0_mm = EXCLUDED.pistoia_et0_mm,
      pistoia_humidity_pct = EXCLUDED.pistoia_humidity_pct,
      pistoia_cloud_cover_pct = EXCLUDED.pistoia_cloud_cover_pct,
      pistoia_wind_max_kmh = EXCLUDED.pistoia_wind_max_kmh,
      pistoia_soil_temp_c = EXCLUDED.pistoia_soil_temp_c,
      pistoia_soil_moisture = EXCLUDED.pistoia_soil_moisture,
      is_rainy_day = EXCLUDED.is_rainy_day,
      is_heavy_rain_day = EXCLUDED.is_heavy_rain_day,
      is_very_heavy_rain_day = EXCLUDED.is_very_heavy_rain_day,
      is_dry_day = EXCLUDED.is_dry_day,
      is_sunny_day = EXCLUDED.is_sunny_day,
      is_cloudy_day = EXCLUDED.is_cloudy_day,
      is_hot_day = EXCLUDED.is_hot_day,
      is_very_hot_day = EXCLUDED.is_very_hot_day,
      is_cold_day = EXCLUDED.is_cold_day,
      is_frost_risk_day = EXCLUDED.is_frost_risk_day,
      rain_3d_mm = EXCLUDED.rain_3d_mm,
      rain_7d_mm = EXCLUDED.rain_7d_mm,
      rain_14d_mm = EXCLUDED.rain_14d_mm,
      sun_hours_3d = EXCLUDED.sun_hours_3d,
      sun_hours_7d = EXCLUDED.sun_hours_7d,
      tavg_3d = EXCLUDED.tavg_3d,
      tavg_7d = EXCLUDED.tavg_7d,
      hot_days_7d = EXCLUDED.hot_days_7d,
      rainy_days_7d = EXCLUDED.rainy_days_7d,
      dry_days_7d = EXCLUDED.dry_days_7d,
      garden_workability_score = EXCLUDED.garden_workability_score,
      garden_visit_score = EXCLUDED.garden_visit_score,
      planting_window_score = EXCLUDED.planting_window_score,
      heat_stress_score = EXCLUDED.heat_stress_score,
      dryness_stress_score = EXCLUDED.dryness_stress_score,
      rain_disruption_score = EXCLUDED.rain_disruption_score,
      score_version = EXCLUDED.score_version,
      updated_at = now()
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_rows
  FROM upserted;

  RETURN QUERY SELECT v_rows, p_from, p_to;
END;
$function$;

CREATE OR REPLACE VIEW public.v_greenhouse_forecast_features_weather_enriched AS
SELECT
  f.data,
  f.famiglia,
  f.fascia_prezzo_iva_inc,
  f.qty_venduta,
  f.imponibile_netto_tot,
  f.num_articoli,
  f.fascia_corretta,
  f.categoria_corretta,
  f.pot_sizes_text,
  f.pot_sizes_json,
  f.articoli_inclusi,
  f.articoli_json,

  COALESCE(w.area_avg_tmin_c, f.tmin_c) AS tmin_c,
  COALESCE(w.area_avg_tmax_c, f.tmax_c) AS tmax_c,
  COALESCE(w.area_avg_tavg_c, f.tavg_c) AS tavg_c,
  COALESCE(w.area_avg_rain_mm, f.rain_mm) AS rain_mm,
  COALESCE(w.area_avg_sun_hours, f.sun_hours) AS sun_hours,

  f.is_holiday,
  f.holiday_name,
  f.dow,
  f.week_num,
  f.month_num,
  f.year_num,
  f.qty_lag_1,
  f.qty_lag_2,
  f.qty_lag_3,
  f.qty_lag_7,
  f.qty_lag_10,
  f.qty_lag_14,
  f.qty_ma_3,
  f.qty_ma_7,
  f.qty_ma_10,
  f.qty_ma_14,
  f.qty_ma_28,
  f.created_at,
  f.updated_at,

  w.source_kind AS weather_source_kind,
  w.location_count AS weather_location_count,
  w.location_codes AS weather_location_codes,

  w.area_avg_tmin_c,
  w.area_avg_tmax_c,
  w.area_avg_tavg_c,
  w.area_min_tmin_c,
  w.area_max_tmax_c,
  w.area_temp_range_c,
  w.area_avg_apparent_tavg_c,
  w.area_avg_rain_mm,
  w.area_max_rain_mm,
  w.area_rainy_locations,
  w.area_heavy_rain_locations,
  w.area_avg_sun_hours,
  w.area_max_sun_hours,
  w.area_avg_shortwave_mj_m2,
  w.area_avg_et0_mm,
  w.area_avg_humidity_pct,
  w.area_avg_cloud_cover_pct,
  w.area_avg_wind_max_kmh,
  w.area_max_wind_gust_kmh,

  w.pistoia_tmin_c,
  w.pistoia_tmax_c,
  w.pistoia_tavg_c,
  w.pistoia_apparent_tavg_c,
  w.pistoia_rain_mm,
  w.pistoia_sun_hours,
  w.pistoia_et0_mm,
  w.pistoia_humidity_pct,
  w.pistoia_cloud_cover_pct,
  w.pistoia_wind_max_kmh,

  w.is_rainy_day,
  w.is_heavy_rain_day,
  w.is_very_heavy_rain_day,
  w.is_dry_day,
  w.is_sunny_day,
  w.is_cloudy_day,
  w.is_hot_day,
  w.is_very_hot_day,
  w.is_cold_day,
  w.is_frost_risk_day,

  w.rain_3d_mm,
  w.rain_7d_mm,
  w.rain_14d_mm,
  w.sun_hours_3d,
  w.sun_hours_7d,
  w.tavg_3d,
  w.tavg_7d,
  w.hot_days_7d,
  w.rainy_days_7d,
  w.dry_days_7d,

  w.garden_workability_score,
  w.garden_visit_score,
  w.planting_window_score,
  w.heat_stress_score,
  w.dryness_stress_score,
  w.rain_disruption_score,
  w.score_version
FROM public.greenhouse_forecast_features_dense f
LEFT JOIN public.greenhouse_weather_ml_features_daily w
  ON w.data = f.data;

COMMENT ON TABLE public.greenhouse_weather_ml_features_daily IS
  'Daily multi-location weather ML feature store derived from gb_weather actuals/forecasts. One row per date.';

COMMENT ON FUNCTION public.refresh_greenhouse_weather_ml_features_daily(date, date) IS
  'Refreshes daily multi-location weather ML features from gb_weather sources for a date range, using actuals where available and latest forecasts otherwise.';

COMMENT ON VIEW public.v_greenhouse_forecast_features_weather_enriched IS
  'Greenhouse forecast dense features enriched with multi-location weather ML features without rewriting the dense table.';
