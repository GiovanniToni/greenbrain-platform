from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.api.v1.auth import get_current_user
from app.db.session import get_db

router = APIRouter(prefix="/api/v1/settings", tags=["settings"])


class GardenCenterSettingsResponse(BaseModel):
    city: str
    lat: Optional[float]
    lon: Optional[float]


class GardenCenterSettingsRequest(BaseModel):
    city: str
    lat: Optional[float] = None
    lon: Optional[float] = None


@router.get("/garden-center", response_model=GardenCenterSettingsResponse)
def get_garden_center_settings(
    _user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = db.execute(
        text("SELECT city, lat, lon FROM public.garden_center_settings LIMIT 1")
    ).mappings().first()

    if not row:
        return GardenCenterSettingsResponse(city="", lat=None, lon=None)

    return GardenCenterSettingsResponse(
        city=row["city"] or "",
        lat=float(row["lat"]) if row["lat"] is not None else None,
        lon=float(row["lon"]) if row["lon"] is not None else None,
    )


@router.post("/garden-center", response_model=GardenCenterSettingsResponse)
def save_garden_center_settings(
    body: GardenCenterSettingsRequest,
    _user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    db.execute(
        text("""
            INSERT INTO public.garden_center_settings (city, lat, lon, updated_at)
            VALUES (:city, :lat, :lon, now())
            ON CONFLICT (id) DO UPDATE
                SET city = EXCLUDED.city,
                    lat  = EXCLUDED.lat,
                    lon  = EXCLUDED.lon,
                    updated_at = now()
        """),
        {"city": body.city, "lat": body.lat, "lon": body.lon},
    )
    db.commit()
    return GardenCenterSettingsResponse(city=body.city, lat=body.lat, lon=body.lon)
