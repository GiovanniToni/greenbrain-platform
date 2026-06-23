from __future__ import annotations

import json
from datetime import date
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request, urlopen


OPEN_METEO_FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
OPEN_METEO_ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive"
OPEN_METEO_PROVIDER = "open_meteo"
OPEN_METEO_USER_AGENT = "GreenBrain-weather-ingestion/1.0"


FORECAST_DAILY_VARIABLES = [
    "weather_code",
    "temperature_2m_max",
    "temperature_2m_min",
    "temperature_2m_mean",
    "apparent_temperature_max",
    "apparent_temperature_min",
    "apparent_temperature_mean",
    "sunrise",
    "sunset",
    "daylight_duration",
    "sunshine_duration",
    "uv_index_max",
    "precipitation_sum",
    "rain_sum",
    "showers_sum",
    "snowfall_sum",
    "precipitation_probability_max",
    "precipitation_hours",
    "wind_speed_10m_max",
    "wind_gusts_10m_max",
    "wind_direction_10m_dominant",
    "shortwave_radiation_sum",
    "et0_fao_evapotranspiration",
    "relative_humidity_2m_mean",
    "cloud_cover_mean",
]


HISTORICAL_DAILY_VARIABLES = [
    "weather_code",
    "temperature_2m_max",
    "temperature_2m_min",
    "temperature_2m_mean",
    "apparent_temperature_max",
    "apparent_temperature_min",
    "apparent_temperature_mean",
    "sunrise",
    "sunset",
    "daylight_duration",
    "sunshine_duration",
    "precipitation_sum",
    "rain_sum",
    "snowfall_sum",
    "precipitation_hours",
    "wind_speed_10m_max",
    "wind_gusts_10m_max",
    "wind_direction_10m_dominant",
    "shortwave_radiation_sum",
    "et0_fao_evapotranspiration",
    "relative_humidity_2m_mean",
    "relative_humidity_2m_max",
    "relative_humidity_2m_min",
    "dew_point_2m_mean",
    "cloud_cover_mean",
    "soil_temperature_0_to_7cm_mean",
    "soil_moisture_0_to_7cm_mean",
]


CURRENT_VARIABLES = [
    "temperature_2m",
    "relative_humidity_2m",
    "apparent_temperature",
    "is_day",
    "precipitation",
    "rain",
    "showers",
    "snowfall",
    "weather_code",
    "cloud_cover",
    "wind_speed_10m",
    "wind_gusts_10m",
]


class OpenMeteoClientError(RuntimeError):
    pass


def _as_float(value: Any) -> float:
    return float(value)


def _as_date_str(value: date | str) -> str:
    if isinstance(value, date):
        return value.isoformat()
    return str(value)


def _http_get_json(url: str, params: dict[str, Any], timeout_seconds: int) -> dict[str, Any]:
    query_params: dict[str, Any] = {}

    for key, value in params.items():
        if value is None:
            continue
        if isinstance(value, (list, tuple)):
            query_params[key] = ",".join(str(v) for v in value)
        else:
            query_params[key] = value

    url_with_query = url + "?" + urlencode(query_params)
    req = Request(
        url_with_query,
        headers={
            "User-Agent": OPEN_METEO_USER_AGENT,
            "Accept": "application/json",
        },
    )

    try:
        with urlopen(req, timeout=timeout_seconds) as response:
            raw = response.read().decode("utf-8")
    except Exception as exc:
        raise OpenMeteoClientError(f"open_meteo_http_failed:{type(exc).__name__}:{exc}") from exc

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise OpenMeteoClientError(f"open_meteo_invalid_json:{exc}") from exc

    if not isinstance(data, dict):
        raise OpenMeteoClientError("open_meteo_unexpected_response_type")

    if data.get("error"):
        reason = data.get("reason") or data.get("message") or "unknown_error"
        raise OpenMeteoClientError(f"open_meteo_error:{reason}")

    return data


def _daily_rows(data: dict[str, Any]) -> list[dict[str, Any]]:
    daily = data.get("daily") or {}
    times = daily.get("time") or []

    if not isinstance(daily, dict):
        raise OpenMeteoClientError("open_meteo_daily_missing")
    if not isinstance(times, list):
        raise OpenMeteoClientError("open_meteo_daily_time_invalid")

    rows: list[dict[str, Any]] = []
    for idx, day in enumerate(times):
        row = {"time": day}
        for key, values in daily.items():
            if key == "time":
                continue
            if isinstance(values, list) and idx < len(values):
                row[key] = values[idx]
            else:
                row[key] = None
        rows.append(row)

    return rows


def fetch_daily_forecast(
    *,
    latitude: float | str,
    longitude: float | str,
    timezone: str = "Europe/Rome",
    forecast_days: int = 10,
    timeout_seconds: int = 30,
) -> dict[str, Any]:
    if forecast_days < 1 or forecast_days > 16:
        raise ValueError("forecast_days must be between 1 and 16")

    data = _http_get_json(
        OPEN_METEO_FORECAST_URL,
        {
            "latitude": _as_float(latitude),
            "longitude": _as_float(longitude),
            "timezone": timezone,
            "forecast_days": forecast_days,
            "daily": FORECAST_DAILY_VARIABLES,
        },
        timeout_seconds=timeout_seconds,
    )

    return {
        "provider": OPEN_METEO_PROVIDER,
        "kind": "forecast",
        "timezone": data.get("timezone"),
        "latitude": data.get("latitude"),
        "longitude": data.get("longitude"),
        "raw": data,
        "daily_rows": _daily_rows(data),
    }


def fetch_historical_daily(
    *,
    latitude: float | str,
    longitude: float | str,
    start_date: date | str,
    end_date: date | str,
    timezone: str = "Europe/Rome",
    timeout_seconds: int = 45,
) -> dict[str, Any]:
    data = _http_get_json(
        OPEN_METEO_ARCHIVE_URL,
        {
            "latitude": _as_float(latitude),
            "longitude": _as_float(longitude),
            "timezone": timezone,
            "start_date": _as_date_str(start_date),
            "end_date": _as_date_str(end_date),
            "daily": HISTORICAL_DAILY_VARIABLES,
        },
        timeout_seconds=timeout_seconds,
    )

    return {
        "provider": OPEN_METEO_PROVIDER,
        "kind": "historical_daily",
        "timezone": data.get("timezone"),
        "latitude": data.get("latitude"),
        "longitude": data.get("longitude"),
        "raw": data,
        "daily_rows": _daily_rows(data),
    }


def fetch_current_conditions(
    *,
    latitude: float | str,
    longitude: float | str,
    timezone: str = "Europe/Rome",
    timeout_seconds: int = 20,
) -> dict[str, Any]:
    data = _http_get_json(
        OPEN_METEO_FORECAST_URL,
        {
            "latitude": _as_float(latitude),
            "longitude": _as_float(longitude),
            "timezone": timezone,
            "current": CURRENT_VARIABLES,
        },
        timeout_seconds=timeout_seconds,
    )

    return {
        "provider": OPEN_METEO_PROVIDER,
        "kind": "current",
        "timezone": data.get("timezone"),
        "latitude": data.get("latitude"),
        "longitude": data.get("longitude"),
        "raw": data,
        "current": data.get("current") or {},
    }
