from __future__ import annotations

from datetime import date, timedelta
from typing import Any

from app.repositories import weather_repository as repo
from app.services.open_meteo_client import (
    OpenMeteoClientError,
    fetch_current_conditions,
    fetch_daily_forecast,
    fetch_historical_daily,
)


DEFAULT_LOCATION_CODE = "pistoia"
MAX_FORECAST_DAYS = 10
MAX_RECENT_ACTUAL_DAYS = 14
MAX_HISTORICAL_BACKFILL_DAYS = 366


class WeatherIngestionError(RuntimeError):
    pass


def _today() -> date:
    return date.today()


def _parse_date(value: str | date) -> date:
    if isinstance(value, date):
        return value
    return date.fromisoformat(str(value))


def _location_or_error(db: Any, location_code: str | None) -> dict[str, Any]:
    clean = (location_code or "").strip().lower()

    if clean:
        location = repo.get_location_by_code(db, clean)
    else:
        location = repo.get_default_location(db)

    if not location:
        raise WeatherIngestionError(f"weather_location_not_found:{clean or 'default'}")

    return location


def _location_client_kwargs(location: dict[str, Any]) -> dict[str, Any]:
    return {
        "latitude": location["latitude"],
        "longitude": location["longitude"],
        "timezone": location.get("timezone") or "Europe/Rome",
    }


def ingest_forecast_for_location(
    db: Any,
    *,
    location_code: str | None = DEFAULT_LOCATION_CODE,
    forecast_days: int = MAX_FORECAST_DAYS,
) -> dict[str, Any]:
    if forecast_days < 1:
        raise WeatherIngestionError("forecast_days_must_be_positive")
    if forecast_days > MAX_FORECAST_DAYS:
        raise WeatherIngestionError(f"forecast_days_limit_exceeded:max_{MAX_FORECAST_DAYS}")

    location = _location_or_error(db, location_code)
    forecast_run_date = _today()

    run_id = repo.create_ingestion_run(
        db,
        run_type="forecast",
        location_id=location["id"],
        date_from=forecast_run_date,
        date_to=forecast_run_date + timedelta(days=forecast_days - 1),
        forecast_days=forecast_days,
        source_params={
            "location_code": location["location_code"],
            "forecast_days": forecast_days,
            "rate_limit_policy": "single_location_no_parallelism",
        },
    )

    try:
        data = fetch_daily_forecast(
            **_location_client_kwargs(location),
            forecast_days=forecast_days,
            timeout_seconds=30,
        )
        rows = data["daily_rows"]
        upserted = repo.upsert_daily_forecast_rows(
            db,
            location_id=location["id"],
            forecast_run_date=forecast_run_date,
            rows=rows,
            provider=data.get("provider") or "open_meteo",
            provider_model=None,
        )

        finished = repo.finish_ingestion_run(
            db,
            run_id=run_id,
            status="ok",
            rows_requested=len(rows),
            rows_upserted=upserted,
            rows_failed=max(0, len(rows) - upserted),
            result_summary={
                "location_code": location["location_code"],
                "forecast_days": forecast_days,
                "rows_received": len(rows),
                "rows_upserted": upserted,
            },
        )

        return {
            "status": "ok",
            "run": finished,
            "location": location,
            "rows_received": len(rows),
            "rows_upserted": upserted,
        }

    except Exception as exc:
        repo.finish_ingestion_run(
            db,
            run_id=run_id,
            status="failed",
            rows_requested=0,
            rows_upserted=0,
            rows_failed=0,
            result_summary={
                "location_code": location["location_code"],
                "forecast_days": forecast_days,
            },
            error_message=str(exc),
        )
        if isinstance(exc, OpenMeteoClientError):
            raise WeatherIngestionError(str(exc)) from exc
        raise


def ingest_current_for_location(
    db: Any,
    *,
    location_code: str | None = DEFAULT_LOCATION_CODE,
) -> dict[str, Any]:
    location = _location_or_error(db, location_code)

    run_id = repo.create_ingestion_run(
        db,
        run_type="current",
        location_id=location["id"],
        source_params={
            "location_code": location["location_code"],
            "rate_limit_policy": "single_location_no_parallelism",
        },
    )

    try:
        data = fetch_current_conditions(
            **_location_client_kwargs(location),
            timeout_seconds=20,
        )
        current = data.get("current") or {}
        upserted = repo.upsert_current_conditions(
            db,
            location_id=location["id"],
            current=current,
            provider=data.get("provider") or "open_meteo",
        )

        finished = repo.finish_ingestion_run(
            db,
            run_id=run_id,
            status="ok",
            rows_requested=1,
            rows_upserted=upserted,
            rows_failed=0 if upserted else 1,
            result_summary={
                "location_code": location["location_code"],
                "current_keys": sorted(current.keys()),
            },
        )

        return {
            "status": "ok",
            "run": finished,
            "location": location,
            "rows_upserted": upserted,
        }

    except Exception as exc:
        repo.finish_ingestion_run(
            db,
            run_id=run_id,
            status="failed",
            rows_requested=1,
            rows_upserted=0,
            rows_failed=1,
            result_summary={"location_code": location["location_code"]},
            error_message=str(exc),
        )
        if isinstance(exc, OpenMeteoClientError):
            raise WeatherIngestionError(str(exc)) from exc
        raise


def ingest_recent_actuals_for_location(
    db: Any,
    *,
    location_code: str | None = DEFAULT_LOCATION_CODE,
    days: int = 10,
    end_date: str | date | None = None,
) -> dict[str, Any]:
    if days < 1:
        raise WeatherIngestionError("recent_actual_days_must_be_positive")
    if days > MAX_RECENT_ACTUAL_DAYS:
        raise WeatherIngestionError(f"recent_actual_days_limit_exceeded:max_{MAX_RECENT_ACTUAL_DAYS}")

    location = _location_or_error(db, location_code)
    resolved_end = _parse_date(end_date) if end_date else _today() - timedelta(days=1)
    resolved_start = resolved_end - timedelta(days=days - 1)

    return ingest_historical_actuals_for_location(
        db,
        location_code=location["location_code"],
        start_date=resolved_start,
        end_date=resolved_end,
        run_type="recent_actuals",
        max_days=MAX_RECENT_ACTUAL_DAYS,
    )


def ingest_historical_actuals_for_location(
    db: Any,
    *,
    location_code: str | None = DEFAULT_LOCATION_CODE,
    start_date: str | date,
    end_date: str | date,
    run_type: str = "historical_backfill",
    max_days: int = MAX_HISTORICAL_BACKFILL_DAYS,
) -> dict[str, Any]:
    location = _location_or_error(db, location_code)
    resolved_start = _parse_date(start_date)
    resolved_end = _parse_date(end_date)

    if resolved_end < resolved_start:
        raise WeatherIngestionError("historical_date_range_invalid")

    total_days = (resolved_end - resolved_start).days + 1
    if total_days > max_days:
        raise WeatherIngestionError(f"historical_date_range_too_large:max_{max_days}_days")

    if run_type not in {"historical_backfill", "recent_actuals", "manual_test"}:
        raise WeatherIngestionError(f"historical_run_type_invalid:{run_type}")

    run_id = repo.create_ingestion_run(
        db,
        run_type=run_type,
        location_id=location["id"],
        date_from=resolved_start,
        date_to=resolved_end,
        source_params={
            "location_code": location["location_code"],
            "days": total_days,
            "rate_limit_policy": "manual_chunked_no_parallelism",
        },
    )

    try:
        data = fetch_historical_daily(
            **_location_client_kwargs(location),
            start_date=resolved_start,
            end_date=resolved_end,
            timeout_seconds=45,
        )
        rows = data["daily_rows"]
        upserted = repo.upsert_daily_actual_rows(
            db,
            location_id=location["id"],
            rows=rows,
            provider=data.get("provider") or "open_meteo",
            provider_model=None,
        )

        finished = repo.finish_ingestion_run(
            db,
            run_id=run_id,
            status="ok",
            rows_requested=len(rows),
            rows_upserted=upserted,
            rows_failed=max(0, len(rows) - upserted),
            result_summary={
                "location_code": location["location_code"],
                "date_from": resolved_start.isoformat(),
                "date_to": resolved_end.isoformat(),
                "days": total_days,
                "rows_received": len(rows),
                "rows_upserted": upserted,
            },
        )

        return {
            "status": "ok",
            "run": finished,
            "location": location,
            "date_from": resolved_start.isoformat(),
            "date_to": resolved_end.isoformat(),
            "rows_received": len(rows),
            "rows_upserted": upserted,
        }

    except Exception as exc:
        repo.finish_ingestion_run(
            db,
            run_id=run_id,
            status="failed",
            rows_requested=0,
            rows_upserted=0,
            rows_failed=0,
            result_summary={
                "location_code": location["location_code"],
                "date_from": resolved_start.isoformat(),
                "date_to": resolved_end.isoformat(),
            },
            error_message=str(exc),
        )
        if isinstance(exc, OpenMeteoClientError):
            raise WeatherIngestionError(str(exc)) from exc
        raise


def ingest_forecast_for_all_active_locations(
    db: Any,
    *,
    forecast_days: int = MAX_FORECAST_DAYS,
) -> dict[str, Any]:
    if forecast_days < 1:
        raise WeatherIngestionError("forecast_days_must_be_positive")
    if forecast_days > MAX_FORECAST_DAYS:
        raise WeatherIngestionError(f"forecast_days_limit_exceeded:max_{MAX_FORECAST_DAYS}")

    locations = repo.get_active_locations(db)
    results: list[dict[str, Any]] = []

    # Explicitly sequential: no parallelism, to stay conservative with Open-Meteo free non-commercial limits.
    for location in locations:
        result = ingest_forecast_for_location(
            db,
            location_code=location["location_code"],
            forecast_days=forecast_days,
        )
        results.append({
            "location_code": location["location_code"],
            "status": result["status"],
            "rows_upserted": result["rows_upserted"],
            "run_id": result["run"]["id"],
        })

    return {
        "status": "ok",
        "locations": len(locations),
        "forecast_days": forecast_days,
        "results": results,
    }


def get_weather_status(db: Any, *, location_code: str | None = DEFAULT_LOCATION_CODE) -> dict[str, Any]:
    location = _location_or_error(db, location_code)
    latest_forecast = repo.get_latest_forecast(db, location_code=location["location_code"], days=MAX_FORECAST_DAYS)
    recent_runs = repo.get_recent_ingestion_runs(db, limit=10)

    return {
        "location": location,
        "latest_forecast_rows": len(latest_forecast),
        "latest_forecast": latest_forecast,
        "recent_runs": recent_runs,
        "limits": {
            "max_forecast_days": MAX_FORECAST_DAYS,
            "max_recent_actual_days": MAX_RECENT_ACTUAL_DAYS,
            "max_historical_backfill_days_per_call": MAX_HISTORICAL_BACKFILL_DAYS,
            "parallelism": "disabled",
        },
    }
