from __future__ import annotations

import json
from datetime import date
from typing import Any, Iterable

from sqlalchemy import text


def _jsonb(value: Any) -> str:
    return json.dumps(value or {}, ensure_ascii=False, default=str)


def _row_to_dict(row: Any) -> dict[str, Any]:
    data = dict(row)
    for key, value in list(data.items()):
        if hasattr(value, "isoformat"):
            data[key] = value.isoformat()
        else:
            data[key] = value
    return data


def _bool_or_none(value: Any) -> bool | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        clean = value.strip().lower()
        if clean in {"1", "true", "t", "yes", "y", "si", "sì"}:
            return True
        if clean in {"0", "false", "f", "no", "n"}:
            return False
    return None


def get_active_locations(db: Any) -> list[dict[str, Any]]:
    rows = db.execute(text("""
        select
          id::text as id,
          location_code,
          display_name,
          municipality,
          province_code,
          region,
          country_code,
          latitude,
          longitude,
          timezone,
          is_default,
          is_active
        from gb_weather.locations
        where is_active = true
        order by location_code;
    """)).mappings().all()
    return [_row_to_dict(r) for r in rows]


def get_location_by_code(db: Any, location_code: str) -> dict[str, Any] | None:
    row = db.execute(
        text("""
            select
              id::text as id,
              location_code,
              display_name,
              municipality,
              province_code,
              region,
              country_code,
              latitude,
              longitude,
              timezone,
              is_default,
              is_active
            from gb_weather.locations
            where location_code = :location_code
              and is_active = true
            limit 1;
        """),
        {"location_code": (location_code or "").strip().lower()},
    ).mappings().first()
    return _row_to_dict(row) if row else None


def get_default_location(db: Any) -> dict[str, Any] | None:
    row = db.execute(text("""
        select
          id::text as id,
          location_code,
          display_name,
          municipality,
          province_code,
          region,
          country_code,
          latitude,
          longitude,
          timezone,
          is_default,
          is_active
        from gb_weather.locations
        where is_default = true
          and is_active = true
        limit 1;
    """)).mappings().first()
    return _row_to_dict(row) if row else None


def create_ingestion_run(
    db: Any,
    *,
    run_type: str,
    location_id: str | None = None,
    provider: str = "open_meteo",
    date_from: str | date | None = None,
    date_to: str | date | None = None,
    forecast_days: int | None = None,
    source_params: dict[str, Any] | None = None,
) -> str:
    row = db.execute(
        text("""
            insert into gb_weather.ingestion_runs (
              provider,
              run_type,
              status,
              location_id,
              date_from,
              date_to,
              forecast_days,
              source_params
            )
            values (
              :provider,
              :run_type,
              'running',
              cast(:location_id as uuid),
              cast(:date_from as date),
              cast(:date_to as date),
              :forecast_days,
              cast(:source_params as jsonb)
            )
            returning id::text as id;
        """),
        {
            "provider": provider,
            "run_type": run_type,
            "location_id": location_id,
            "date_from": str(date_from) if date_from else None,
            "date_to": str(date_to) if date_to else None,
            "forecast_days": forecast_days,
            "source_params": _jsonb(source_params),
        },
    ).mappings().first()

    if not row:
        raise RuntimeError("weather_ingestion_run_insert_failed")
    return str(row["id"])


def finish_ingestion_run(
    db: Any,
    *,
    run_id: str,
    status: str,
    rows_requested: int = 0,
    rows_upserted: int = 0,
    rows_failed: int = 0,
    result_summary: dict[str, Any] | None = None,
    error_message: str | None = None,
) -> dict[str, Any]:
    row = db.execute(
        text("""
            update gb_weather.ingestion_runs
            set
              status = :status,
              finished_at = now(),
              rows_requested = :rows_requested,
              rows_upserted = :rows_upserted,
              rows_failed = :rows_failed,
              result_summary = cast(:result_summary as jsonb),
              error_message = :error_message
            where id = cast(:run_id as uuid)
            returning id::text as id, status, rows_requested, rows_upserted, rows_failed, finished_at;
        """),
        {
            "run_id": run_id,
            "status": status,
            "rows_requested": rows_requested,
            "rows_upserted": rows_upserted,
            "rows_failed": rows_failed,
            "result_summary": _jsonb(result_summary),
            "error_message": error_message,
        },
    ).mappings().first()

    if not row:
        raise RuntimeError(f"weather_ingestion_run_finish_failed:{run_id}")
    return _row_to_dict(row)


def _horizon_days(run_date: str | date, forecast_date: str | date) -> int:
    rd = run_date if isinstance(run_date, date) else date.fromisoformat(str(run_date))
    fd = forecast_date if isinstance(forecast_date, date) else date.fromisoformat(str(forecast_date))
    return (fd - rd).days


def upsert_daily_forecast_rows(
    db: Any,
    *,
    location_id: str,
    forecast_run_date: str | date,
    rows: Iterable[dict[str, Any]],
    provider: str = "open_meteo",
    provider_model: str | None = None,
) -> int:
    count = 0

    for item in rows:
        forecast_date = item.get("time")
        if not forecast_date:
            continue

        params = {
            "location_id": location_id,
            "forecast_run_date": str(forecast_run_date),
            "forecast_date": str(forecast_date),
            "provider": provider,
            "provider_model": provider_model,
            "forecast_horizon_days": _horizon_days(forecast_run_date, str(forecast_date)),
            "weather_code": item.get("weather_code"),
            "temperature_2m_max_c": item.get("temperature_2m_max"),
            "temperature_2m_min_c": item.get("temperature_2m_min"),
            "temperature_2m_mean_c": item.get("temperature_2m_mean"),
            "apparent_temperature_max_c": item.get("apparent_temperature_max"),
            "apparent_temperature_min_c": item.get("apparent_temperature_min"),
            "apparent_temperature_mean_c": item.get("apparent_temperature_mean"),
            "sunrise_local": item.get("sunrise"),
            "sunset_local": item.get("sunset"),
            "daylight_duration_seconds": item.get("daylight_duration"),
            "sunshine_duration_seconds": item.get("sunshine_duration"),
            "uv_index_max": item.get("uv_index_max"),
            "precipitation_sum_mm": item.get("precipitation_sum"),
            "rain_sum_mm": item.get("rain_sum"),
            "showers_sum_mm": item.get("showers_sum"),
            "snowfall_sum_cm": item.get("snowfall_sum"),
            "precipitation_probability_max_pct": item.get("precipitation_probability_max"),
            "precipitation_hours": item.get("precipitation_hours"),
            "wind_speed_10m_max_kmh": item.get("wind_speed_10m_max"),
            "wind_gusts_10m_max_kmh": item.get("wind_gusts_10m_max"),
            "wind_direction_10m_dominant_deg": item.get("wind_direction_10m_dominant"),
            "shortwave_radiation_sum_mj_m2": item.get("shortwave_radiation_sum"),
            "et0_fao_evapotranspiration_mm": item.get("et0_fao_evapotranspiration"),
            "relative_humidity_2m_mean_pct": item.get("relative_humidity_2m_mean"),
            "cloud_cover_mean_pct": item.get("cloud_cover_mean"),
            "source_payload": _jsonb(item),
        }

        db.execute(text("""
            insert into gb_weather.daily_forecasts (
              location_id,
              forecast_run_date,
              forecast_date,
              provider,
              provider_model,
              forecast_horizon_days,
              weather_code,
              temperature_2m_max_c,
              temperature_2m_min_c,
              temperature_2m_mean_c,
              apparent_temperature_max_c,
              apparent_temperature_min_c,
              apparent_temperature_mean_c,
              sunrise_local,
              sunset_local,
              daylight_duration_seconds,
              sunshine_duration_seconds,
              uv_index_max,
              precipitation_sum_mm,
              rain_sum_mm,
              showers_sum_mm,
              snowfall_sum_cm,
              precipitation_probability_max_pct,
              precipitation_hours,
              wind_speed_10m_max_kmh,
              wind_gusts_10m_max_kmh,
              wind_direction_10m_dominant_deg,
              shortwave_radiation_sum_mj_m2,
              et0_fao_evapotranspiration_mm,
              relative_humidity_2m_mean_pct,
              cloud_cover_mean_pct,
              source_payload,
              fetched_at,
              updated_at
            )
            values (
              cast(:location_id as uuid),
              cast(:forecast_run_date as date),
              cast(:forecast_date as date),
              :provider,
              :provider_model,
              :forecast_horizon_days,
              :weather_code,
              :temperature_2m_max_c,
              :temperature_2m_min_c,
              :temperature_2m_mean_c,
              :apparent_temperature_max_c,
              :apparent_temperature_min_c,
              :apparent_temperature_mean_c,
              cast(:sunrise_local as timestamp),
              cast(:sunset_local as timestamp),
              :daylight_duration_seconds,
              :sunshine_duration_seconds,
              :uv_index_max,
              :precipitation_sum_mm,
              :rain_sum_mm,
              :showers_sum_mm,
              :snowfall_sum_cm,
              :precipitation_probability_max_pct,
              :precipitation_hours,
              :wind_speed_10m_max_kmh,
              :wind_gusts_10m_max_kmh,
              :wind_direction_10m_dominant_deg,
              :shortwave_radiation_sum_mj_m2,
              :et0_fao_evapotranspiration_mm,
              :relative_humidity_2m_mean_pct,
              :cloud_cover_mean_pct,
              cast(:source_payload as jsonb),
              now(),
              now()
            )
            on conflict (location_id, forecast_run_date, forecast_date, provider)
            do update set
              provider_model = excluded.provider_model,
              forecast_horizon_days = excluded.forecast_horizon_days,
              weather_code = excluded.weather_code,
              temperature_2m_max_c = excluded.temperature_2m_max_c,
              temperature_2m_min_c = excluded.temperature_2m_min_c,
              temperature_2m_mean_c = excluded.temperature_2m_mean_c,
              apparent_temperature_max_c = excluded.apparent_temperature_max_c,
              apparent_temperature_min_c = excluded.apparent_temperature_min_c,
              apparent_temperature_mean_c = excluded.apparent_temperature_mean_c,
              sunrise_local = excluded.sunrise_local,
              sunset_local = excluded.sunset_local,
              daylight_duration_seconds = excluded.daylight_duration_seconds,
              sunshine_duration_seconds = excluded.sunshine_duration_seconds,
              uv_index_max = excluded.uv_index_max,
              precipitation_sum_mm = excluded.precipitation_sum_mm,
              rain_sum_mm = excluded.rain_sum_mm,
              showers_sum_mm = excluded.showers_sum_mm,
              snowfall_sum_cm = excluded.snowfall_sum_cm,
              precipitation_probability_max_pct = excluded.precipitation_probability_max_pct,
              precipitation_hours = excluded.precipitation_hours,
              wind_speed_10m_max_kmh = excluded.wind_speed_10m_max_kmh,
              wind_gusts_10m_max_kmh = excluded.wind_gusts_10m_max_kmh,
              wind_direction_10m_dominant_deg = excluded.wind_direction_10m_dominant_deg,
              shortwave_radiation_sum_mj_m2 = excluded.shortwave_radiation_sum_mj_m2,
              et0_fao_evapotranspiration_mm = excluded.et0_fao_evapotranspiration_mm,
              relative_humidity_2m_mean_pct = excluded.relative_humidity_2m_mean_pct,
              cloud_cover_mean_pct = excluded.cloud_cover_mean_pct,
              source_payload = excluded.source_payload,
              fetched_at = now(),
              updated_at = now();
        """), params)

        count += 1

    return count


def upsert_daily_actual_rows(
    db: Any,
    *,
    location_id: str,
    rows: Iterable[dict[str, Any]],
    provider: str = "open_meteo",
    provider_model: str | None = None,
) -> int:
    count = 0

    for item in rows:
        weather_date = item.get("time")
        if not weather_date:
            continue

        params = {
            "location_id": location_id,
            "weather_date": str(weather_date),
            "provider": provider,
            "provider_model": provider_model,
            "weather_code": item.get("weather_code"),
            "temperature_2m_max_c": item.get("temperature_2m_max"),
            "temperature_2m_min_c": item.get("temperature_2m_min"),
            "temperature_2m_mean_c": item.get("temperature_2m_mean"),
            "apparent_temperature_max_c": item.get("apparent_temperature_max"),
            "apparent_temperature_min_c": item.get("apparent_temperature_min"),
            "apparent_temperature_mean_c": item.get("apparent_temperature_mean"),
            "sunrise_local": item.get("sunrise"),
            "sunset_local": item.get("sunset"),
            "daylight_duration_seconds": item.get("daylight_duration"),
            "sunshine_duration_seconds": item.get("sunshine_duration"),
            "precipitation_sum_mm": item.get("precipitation_sum"),
            "rain_sum_mm": item.get("rain_sum"),
            "snowfall_sum_cm": item.get("snowfall_sum"),
            "precipitation_hours": item.get("precipitation_hours"),
            "wind_speed_10m_max_kmh": item.get("wind_speed_10m_max"),
            "wind_gusts_10m_max_kmh": item.get("wind_gusts_10m_max"),
            "wind_direction_10m_dominant_deg": item.get("wind_direction_10m_dominant"),
            "shortwave_radiation_sum_mj_m2": item.get("shortwave_radiation_sum"),
            "et0_fao_evapotranspiration_mm": item.get("et0_fao_evapotranspiration"),
            "relative_humidity_2m_mean_pct": item.get("relative_humidity_2m_mean"),
            "relative_humidity_2m_max_pct": item.get("relative_humidity_2m_max"),
            "relative_humidity_2m_min_pct": item.get("relative_humidity_2m_min"),
            "dew_point_2m_mean_c": item.get("dew_point_2m_mean"),
            "cloud_cover_mean_pct": item.get("cloud_cover_mean"),
            "soil_temperature_0_to_7cm_mean_c": item.get("soil_temperature_0_to_7cm_mean"),
            "soil_moisture_0_to_7cm_mean_m3_m3": item.get("soil_moisture_0_to_7cm_mean"),
            "source_payload": _jsonb(item),
        }

        db.execute(text("""
            insert into gb_weather.daily_actuals (
              location_id,
              weather_date,
              provider,
              provider_model,
              weather_code,
              temperature_2m_max_c,
              temperature_2m_min_c,
              temperature_2m_mean_c,
              apparent_temperature_max_c,
              apparent_temperature_min_c,
              apparent_temperature_mean_c,
              sunrise_local,
              sunset_local,
              daylight_duration_seconds,
              sunshine_duration_seconds,
              precipitation_sum_mm,
              rain_sum_mm,
              snowfall_sum_cm,
              precipitation_hours,
              wind_speed_10m_max_kmh,
              wind_gusts_10m_max_kmh,
              wind_direction_10m_dominant_deg,
              shortwave_radiation_sum_mj_m2,
              et0_fao_evapotranspiration_mm,
              relative_humidity_2m_mean_pct,
              relative_humidity_2m_max_pct,
              relative_humidity_2m_min_pct,
              dew_point_2m_mean_c,
              cloud_cover_mean_pct,
              soil_temperature_0_to_7cm_mean_c,
              soil_moisture_0_to_7cm_mean_m3_m3,
              source_payload,
              fetched_at,
              updated_at
            )
            values (
              cast(:location_id as uuid),
              cast(:weather_date as date),
              :provider,
              :provider_model,
              :weather_code,
              :temperature_2m_max_c,
              :temperature_2m_min_c,
              :temperature_2m_mean_c,
              :apparent_temperature_max_c,
              :apparent_temperature_min_c,
              :apparent_temperature_mean_c,
              cast(:sunrise_local as timestamp),
              cast(:sunset_local as timestamp),
              :daylight_duration_seconds,
              :sunshine_duration_seconds,
              :precipitation_sum_mm,
              :rain_sum_mm,
              :snowfall_sum_cm,
              :precipitation_hours,
              :wind_speed_10m_max_kmh,
              :wind_gusts_10m_max_kmh,
              :wind_direction_10m_dominant_deg,
              :shortwave_radiation_sum_mj_m2,
              :et0_fao_evapotranspiration_mm,
              :relative_humidity_2m_mean_pct,
              :relative_humidity_2m_max_pct,
              :relative_humidity_2m_min_pct,
              :dew_point_2m_mean_c,
              :cloud_cover_mean_pct,
              :soil_temperature_0_to_7cm_mean_c,
              :soil_moisture_0_to_7cm_mean_m3_m3,
              cast(:source_payload as jsonb),
              now(),
              now()
            )
            on conflict (location_id, weather_date, provider)
            do update set
              provider_model = excluded.provider_model,
              weather_code = excluded.weather_code,
              temperature_2m_max_c = excluded.temperature_2m_max_c,
              temperature_2m_min_c = excluded.temperature_2m_min_c,
              temperature_2m_mean_c = excluded.temperature_2m_mean_c,
              apparent_temperature_max_c = excluded.apparent_temperature_max_c,
              apparent_temperature_min_c = excluded.apparent_temperature_min_c,
              apparent_temperature_mean_c = excluded.apparent_temperature_mean_c,
              sunrise_local = excluded.sunrise_local,
              sunset_local = excluded.sunset_local,
              daylight_duration_seconds = excluded.daylight_duration_seconds,
              sunshine_duration_seconds = excluded.sunshine_duration_seconds,
              precipitation_sum_mm = excluded.precipitation_sum_mm,
              rain_sum_mm = excluded.rain_sum_mm,
              snowfall_sum_cm = excluded.snowfall_sum_cm,
              precipitation_hours = excluded.precipitation_hours,
              wind_speed_10m_max_kmh = excluded.wind_speed_10m_max_kmh,
              wind_gusts_10m_max_kmh = excluded.wind_gusts_10m_max_kmh,
              wind_direction_10m_dominant_deg = excluded.wind_direction_10m_dominant_deg,
              shortwave_radiation_sum_mj_m2 = excluded.shortwave_radiation_sum_mj_m2,
              et0_fao_evapotranspiration_mm = excluded.et0_fao_evapotranspiration_mm,
              relative_humidity_2m_mean_pct = excluded.relative_humidity_2m_mean_pct,
              relative_humidity_2m_max_pct = excluded.relative_humidity_2m_max_pct,
              relative_humidity_2m_min_pct = excluded.relative_humidity_2m_min_pct,
              dew_point_2m_mean_c = excluded.dew_point_2m_mean_c,
              cloud_cover_mean_pct = excluded.cloud_cover_mean_pct,
              soil_temperature_0_to_7cm_mean_c = excluded.soil_temperature_0_to_7cm_mean_c,
              soil_moisture_0_to_7cm_mean_m3_m3 = excluded.soil_moisture_0_to_7cm_mean_m3_m3,
              source_payload = excluded.source_payload,
              fetched_at = now(),
              updated_at = now();
        """), params)

        count += 1

    return count


def upsert_current_conditions(
    db: Any,
    *,
    location_id: str,
    current: dict[str, Any],
    provider: str = "open_meteo",
) -> int:
    db.execute(
        text("""
            insert into gb_weather.current_conditions (
              location_id,
              provider,
              observed_at,
              temperature_2m_c,
              relative_humidity_2m_pct,
              apparent_temperature_c,
              is_day,
              precipitation_mm,
              rain_mm,
              showers_mm,
              snowfall_cm,
              weather_code,
              cloud_cover_pct,
              wind_speed_10m_kmh,
              wind_gusts_10m_kmh,
              source_payload,
              fetched_at,
              updated_at
            )
            values (
              cast(:location_id as uuid),
              :provider,
              cast(:observed_at as timestamptz),
              :temperature_2m_c,
              :relative_humidity_2m_pct,
              :apparent_temperature_c,
              cast(:is_day as boolean),
              :precipitation_mm,
              :rain_mm,
              :showers_mm,
              :snowfall_cm,
              :weather_code,
              :cloud_cover_pct,
              :wind_speed_10m_kmh,
              :wind_gusts_10m_kmh,
              cast(:source_payload as jsonb),
              now(),
              now()
            )
            on conflict (location_id, provider)
            do update set
              observed_at = excluded.observed_at,
              temperature_2m_c = excluded.temperature_2m_c,
              relative_humidity_2m_pct = excluded.relative_humidity_2m_pct,
              apparent_temperature_c = excluded.apparent_temperature_c,
              is_day = excluded.is_day,
              precipitation_mm = excluded.precipitation_mm,
              rain_mm = excluded.rain_mm,
              showers_mm = excluded.showers_mm,
              snowfall_cm = excluded.snowfall_cm,
              weather_code = excluded.weather_code,
              cloud_cover_pct = excluded.cloud_cover_pct,
              wind_speed_10m_kmh = excluded.wind_speed_10m_kmh,
              wind_gusts_10m_kmh = excluded.wind_gusts_10m_kmh,
              source_payload = excluded.source_payload,
              fetched_at = now(),
              updated_at = now();
        """),
        {
            "location_id": location_id,
            "provider": provider,
            "observed_at": current.get("time"),
            "temperature_2m_c": current.get("temperature_2m"),
            "relative_humidity_2m_pct": current.get("relative_humidity_2m"),
            "apparent_temperature_c": current.get("apparent_temperature"),
            "is_day": _bool_or_none(current.get("is_day")),
            "precipitation_mm": current.get("precipitation"),
            "rain_mm": current.get("rain"),
            "showers_mm": current.get("showers"),
            "snowfall_cm": current.get("snowfall"),
            "weather_code": current.get("weather_code"),
            "cloud_cover_pct": current.get("cloud_cover"),
            "wind_speed_10m_kmh": current.get("wind_speed_10m"),
            "wind_gusts_10m_kmh": current.get("wind_gusts_10m"),
            "source_payload": _jsonb(current),
        },
    )
    return 1


def get_latest_forecast(
    db: Any,
    *,
    location_code: str,
    days: int = 10,
) -> list[dict[str, Any]]:
    rows = db.execute(
        text("""
            select
              l.location_code,
              l.display_name,
              f.forecast_run_date,
              f.forecast_date,
              f.forecast_horizon_days,
              f.weather_code,
              f.temperature_2m_max_c,
              f.temperature_2m_min_c,
              f.temperature_2m_mean_c,
              f.precipitation_sum_mm,
              f.rain_sum_mm,
              f.precipitation_probability_max_pct,
              f.sunshine_duration_seconds,
              f.cloud_cover_mean_pct,
              f.fetched_at
            from gb_weather.v_latest_forecast_10d f
            join gb_weather.locations l
              on l.id = f.location_id
            where l.location_code = :location_code
              and f.forecast_horizon_days between 0 and :days
            order by f.forecast_date asc;
        """),
        {
            "location_code": (location_code or "").strip().lower(),
            "days": days,
        },
    ).mappings().all()
    return [_row_to_dict(r) for r in rows]


def get_daily_actuals(
    db: Any,
    *,
    location_code: str,
    date_from: str | date,
    date_to: str | date,
) -> list[dict[str, Any]]:
    rows = db.execute(
        text("""
            select
              l.location_code,
              l.display_name,
              a.weather_date,
              a.temperature_2m_min_c,
              a.temperature_2m_max_c,
              a.temperature_2m_mean_c,
              a.precipitation_sum_mm,
              a.rain_sum_mm,
              a.sunshine_duration_seconds,
              a.fetched_at
            from gb_weather.daily_actuals a
            join gb_weather.locations l
              on l.id = a.location_id
            where l.location_code = :location_code
              and a.weather_date between cast(:date_from as date) and cast(:date_to as date)
            order by a.weather_date asc;
        """),
        {
            "location_code": (location_code or "").strip().lower(),
            "date_from": str(date_from),
            "date_to": str(date_to),
        },
    ).mappings().all()
    return [_row_to_dict(r) for r in rows]


def get_recent_ingestion_runs(db: Any, *, limit: int = 50) -> list[dict[str, Any]]:
    rows = db.execute(
        text("""
            select
              r.id::text as id,
              r.provider,
              r.run_type,
              r.status,
              l.location_code,
              l.display_name,
              r.date_from,
              r.date_to,
              r.forecast_days,
              r.started_at,
              r.finished_at,
              r.rows_requested,
              r.rows_upserted,
              r.rows_failed,
              r.result_summary,
              r.error_message
            from gb_weather.ingestion_runs r
            left join gb_weather.locations l
              on l.id = r.location_id
            order by r.started_at desc
            limit :limit;
        """),
        {"limit": limit},
    ).mappings().all()
    return [_row_to_dict(r) for r in rows]
