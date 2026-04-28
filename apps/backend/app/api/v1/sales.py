from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text

from app.db.session import get_db
from app.api.v1.auth import require_admin

router = APIRouter(prefix="/api/v1/sales", tags=["sales"])


@router.get("/summary")
def sales_summary(
    date_from: str = Query(..., description="YYYY-MM-DD"),
    date_to: str = Query(..., description="YYYY-MM-DD"),
    limit: int = Query(default=50, ge=1, le=500),
    db: Session = Depends(get_db),
    _: dict = Depends(require_admin),
):
    try:
        result = db.execute(
            text("""
                SELECT
                    entity_key_lc AS famiglia,
                    SUM(qty_venduta_tot)       AS qty_tot,
                    SUM(imponibile_netto_tot)  AS imp_tot
                FROM core_analytics__series_daily_famiglia_lc
                WHERE data >= :date_from
                  AND data <= :date_to
                GROUP BY entity_key_lc
                ORDER BY qty_tot DESC
                LIMIT :limit
            """),
            {"date_from": date_from, "date_to": date_to, "limit": limit},
        )
        rows = [dict(r._mapping) for r in result]
        return {"date_from": date_from, "date_to": date_to, "count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"sales/summary failed: {str(e)}")


@router.get("/timeseries")
def sales_timeseries(
    famiglia: str = Query(..., description="famiglia key (lowercase)"),
    date_from: str = Query(..., description="YYYY-MM-DD"),
    date_to: str = Query(..., description="YYYY-MM-DD"),
    db: Session = Depends(get_db),
    _: dict = Depends(require_admin),
):
    try:
        result = db.execute(
            text("""
                SELECT
                    data,
                    qty_venduta_tot,
                    imponibile_netto_tot,
                    qty_forecast_tot,
                    dow,
                    is_holiday,
                    holiday_name
                FROM core_analytics__series_daily_famiglia_lc
                WHERE entity_key_lc = :famiglia
                  AND data >= :date_from
                  AND data <= :date_to
                ORDER BY data
            """),
            {"famiglia": famiglia, "date_from": date_from, "date_to": date_to},
        )
        rows = [dict(r._mapping) for r in result]
        return {"famiglia": famiglia, "count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"sales/timeseries failed: {str(e)}")
