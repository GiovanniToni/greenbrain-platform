from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.api.v1.auth import require_platform_access
from app.db.session import get_db
from app.repositories import weather_repository as repo
from app.services.weather_ingestion_service import (
    DEFAULT_LOCATION_CODE,
    MAX_FORECAST_DAYS,
    MAX_HISTORICAL_BACKFILL_DAYS,
    MAX_RECENT_ACTUAL_DAYS,
    WeatherIngestionError,
    get_weather_status,
    ingest_current_for_location,
    ingest_forecast_for_all_active_locations,
    ingest_forecast_for_location,
    ingest_historical_actuals_for_location,
    ingest_recent_actuals_for_location,
)

router = APIRouter(prefix="/api/v1/weather", tags=["weather"])


def _http_status_for_weather_error(error: Exception) -> int:
    detail = str(error)

    if "not_found" in detail:
        return 404
    if (
        "limit_exceeded" in detail
        or "too_large" in detail
        or "invalid" in detail
        or "must_be" in detail
        or "date_range" in detail
    ):
        return 400
    if "open_meteo" in detail:
        return 502

    return 500


def _commit_or_rollback(db: Session, ok: bool) -> None:
    if ok:
        db.commit()
    else:
        db.rollback()


@router.get("/locations")
def weather_locations(
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        items = repo.get_active_locations(db)
        return {"count": len(items), "items": items}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"weather locations failed: {str(e)}")


@router.get("/status")
def weather_status(
    location_code: str = Query(default=DEFAULT_LOCATION_CODE),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        return get_weather_status(db, location_code=location_code)
    except WeatherIngestionError as e:
        raise HTTPException(status_code=_http_status_for_weather_error(e), detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"weather status failed: {str(e)}")


@router.get("/forecast")
def weather_forecast(
    location_code: str = Query(default=DEFAULT_LOCATION_CODE),
    days: int = Query(default=MAX_FORECAST_DAYS, ge=1, le=MAX_FORECAST_DAYS),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        items = repo.get_latest_forecast(db, location_code=location_code, days=days)
        return {"count": len(items), "items": items}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"weather forecast failed: {str(e)}")


@router.get("/actuals")
def weather_actuals(
    location_code: str = Query(default=DEFAULT_LOCATION_CODE),
    date_from: str = Query(..., description="YYYY-MM-DD"),
    date_to: str = Query(..., description="YYYY-MM-DD"),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        items = repo.get_daily_actuals(
            db,
            location_code=location_code,
            date_from=date_from,
            date_to=date_to,
        )
        return {"count": len(items), "items": items}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"weather actuals failed: {str(e)}")


@router.get("/ingestion-runs")
def weather_ingestion_runs(
    limit: int = Query(default=50, ge=1, le=200),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        items = repo.get_recent_ingestion_runs(db, limit=limit)
        return {"count": len(items), "items": items}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"weather ingestion runs failed: {str(e)}")


@router.post("/admin/ingest-forecast")
def weather_admin_ingest_forecast(
    location_code: str = Query(default=DEFAULT_LOCATION_CODE),
    forecast_days: int = Query(default=MAX_FORECAST_DAYS, ge=1, le=MAX_FORECAST_DAYS),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        result = ingest_forecast_for_location(
            db,
            location_code=location_code,
            forecast_days=forecast_days,
        )
        _commit_or_rollback(db, ok=True)
        return result
    except WeatherIngestionError as e:
        try:
            _commit_or_rollback(db, ok=True)
        except Exception:
            _commit_or_rollback(db, ok=False)
        raise HTTPException(status_code=_http_status_for_weather_error(e), detail=str(e))
    except Exception as e:
        _commit_or_rollback(db, ok=False)
        raise HTTPException(status_code=500, detail=f"weather ingest forecast failed: {str(e)}")


@router.post("/admin/ingest-forecast-all")
def weather_admin_ingest_forecast_all(
    forecast_days: int = Query(default=MAX_FORECAST_DAYS, ge=1, le=MAX_FORECAST_DAYS),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        result = ingest_forecast_for_all_active_locations(
            db,
            forecast_days=forecast_days,
        )
        _commit_or_rollback(db, ok=True)
        return result
    except WeatherIngestionError as e:
        try:
            _commit_or_rollback(db, ok=True)
        except Exception:
            _commit_or_rollback(db, ok=False)
        raise HTTPException(status_code=_http_status_for_weather_error(e), detail=str(e))
    except Exception as e:
        _commit_or_rollback(db, ok=False)
        raise HTTPException(status_code=500, detail=f"weather ingest forecast all failed: {str(e)}")


@router.post("/admin/ingest-current")
def weather_admin_ingest_current(
    location_code: str = Query(default=DEFAULT_LOCATION_CODE),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        result = ingest_current_for_location(db, location_code=location_code)
        _commit_or_rollback(db, ok=True)
        return result
    except WeatherIngestionError as e:
        try:
            _commit_or_rollback(db, ok=True)
        except Exception:
            _commit_or_rollback(db, ok=False)
        raise HTTPException(status_code=_http_status_for_weather_error(e), detail=str(e))
    except Exception as e:
        _commit_or_rollback(db, ok=False)
        raise HTTPException(status_code=500, detail=f"weather ingest current failed: {str(e)}")


@router.post("/admin/ingest-recent-actuals")
def weather_admin_ingest_recent_actuals(
    location_code: str = Query(default=DEFAULT_LOCATION_CODE),
    days: int = Query(default=10, ge=1, le=MAX_RECENT_ACTUAL_DAYS),
    end_date: str | None = Query(default=None, description="YYYY-MM-DD, defaults to yesterday"),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        result = ingest_recent_actuals_for_location(
            db,
            location_code=location_code,
            days=days,
            end_date=end_date,
        )
        _commit_or_rollback(db, ok=True)
        return result
    except WeatherIngestionError as e:
        try:
            _commit_or_rollback(db, ok=True)
        except Exception:
            _commit_or_rollback(db, ok=False)
        raise HTTPException(status_code=_http_status_for_weather_error(e), detail=str(e))
    except Exception as e:
        _commit_or_rollback(db, ok=False)
        raise HTTPException(status_code=500, detail=f"weather ingest recent actuals failed: {str(e)}")


@router.post("/admin/backfill")
def weather_admin_backfill(
    location_code: str = Query(default=DEFAULT_LOCATION_CODE),
    start_date: str = Query(..., description="YYYY-MM-DD"),
    end_date: str = Query(..., description="YYYY-MM-DD"),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        result = ingest_historical_actuals_for_location(
            db,
            location_code=location_code,
            start_date=start_date,
            end_date=end_date,
            run_type="historical_backfill",
            max_days=MAX_HISTORICAL_BACKFILL_DAYS,
        )
        _commit_or_rollback(db, ok=True)
        return result
    except WeatherIngestionError as e:
        try:
            _commit_or_rollback(db, ok=True)
        except Exception:
            _commit_or_rollback(db, ok=False)
        raise HTTPException(status_code=_http_status_for_weather_error(e), detail=str(e))
    except Exception as e:
        _commit_or_rollback(db, ok=False)
        raise HTTPException(status_code=500, detail=f"weather backfill failed: {str(e)}")
