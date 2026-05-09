from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.api.v1.auth import require_platform_access

router = APIRouter(prefix="/api/v1/forecast", tags=["forecast"])


@router.get("/summary")
def forecast_summary(db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),):
    query = text("""
        SELECT
            COUNT(*) AS total_rows,
            MIN(data) AS min_date,
            MAX(data) AS max_date,
            COUNT(DISTINCT famiglia) AS total_families,
            COUNT(DISTINCT fascia_prezzo_iva_inc) AS total_price_bands
        FROM public.greenhouse_forecast_results_v2
    """)
    row = db.execute(query).mappings().first()
    return dict(row) if row else {}


@router.get("/series")
def forecast_series(
    famiglia: str = Query(..., description="famiglia key (case-insensitive)"),
    date_from: str = Query(..., description="YYYY-MM-DD"),
    date_to: str = Query(..., description="YYYY-MM-DD"),
    fascia_prezzo: Optional[str] = Query(default=None, description="Optional fascia_prezzo_iva_inc filter (case-insensitive)"),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        if fascia_prezzo and fascia_prezzo.strip():
            result = db.execute(
                text("""
                    SELECT data, fascia_prezzo_iva_inc, qty_forecast
                    FROM public.greenhouse_forecast_results_v2
                    WHERE famiglia ILIKE :famiglia
                      AND data >= :date_from
                      AND data <= :date_to
                      AND fascia_prezzo_iva_inc ILIKE :fp
                    ORDER BY data ASC
                """),
                {"famiglia": famiglia, "date_from": date_from, "date_to": date_to, "fp": fascia_prezzo.strip()},
            )
        else:
            result = db.execute(
                text("""
                    SELECT data, fascia_prezzo_iva_inc, qty_forecast
                    FROM public.greenhouse_forecast_results_v2
                    WHERE famiglia ILIKE :famiglia
                      AND data >= :date_from
                      AND data <= :date_to
                    ORDER BY data ASC
                """),
                {"famiglia": famiglia, "date_from": date_from, "date_to": date_to},
            )
        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"forecast/series failed: {str(e)}")


@router.get("/sample")
def forecast_sample(
    limit: int = Query(default=10, ge=1, le=100),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    query = text("""
        SELECT famiglia, fascia_prezzo_iva_inc, data, qty_forecast
        FROM public.greenhouse_forecast_results_v2
        ORDER BY data DESC, famiglia ASC
        LIMIT :limit
    """)
    rows = db.execute(query, {"limit": limit}).mappings().all()
    return {
        "count": len(rows),
        "items": [dict(r) for r in rows],
    }
