from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import text

from app.db.session import get_db
from app.api.v1.auth import require_admin

router = APIRouter(prefix="/api/v1/dashboard", tags=["dashboard"])


@router.get("/kpis")
def get_dashboard_kpis(db: Session = Depends(get_db),
    _: dict = Depends(require_admin),):
    try:
        result = db.execute(text("SELECT * FROM dashboard__kpis_v2()"))
        row = result.mappings().first()
        return dict(row) if row else {}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"dashboard__kpis_v2 RPC failed: {str(e)}")


@router.get("/sales-weekly")
def get_sales_weekly(db: Session = Depends(get_db),
    _: dict = Depends(require_admin),):
    try:
        result = db.execute(
            text("SELECT data, imp_tot FROM dashboard__sales_weekly ORDER BY data ASC")
        )
        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"sales-weekly query failed: {str(e)}")


@router.get("/sales-monthly")
def get_sales_monthly(db: Session = Depends(get_db),
    _: dict = Depends(require_admin),):
    try:
        result = db.execute(
            text("SELECT data, imp_tot FROM dashboard__sales_monthly ORDER BY data ASC")
        )
        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"sales-monthly query failed: {str(e)}")


@router.get("/sales-yearly")
def get_sales_yearly(db: Session = Depends(get_db),
    _: dict = Depends(require_admin),):
    try:
        result = db.execute(
            text("SELECT data, imp_tot FROM dashboard__sales_yearly ORDER BY data ASC")
        )
        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"sales-yearly query failed: {str(e)}")


@router.get("/reorder-suggestions")
def get_reorder_suggestions(
    limit: int = Query(default=12, ge=1, le=200),
    db: Session = Depends(get_db),
    _: dict = Depends(require_admin),
):
    try:
        result = db.execute(
            text("""
                SELECT famiglia, fascia_prezzo_iva_inc, categoria_corretta, fascia_corretta,
                       pot_sizes_text, qty_giacenza, qty_da_ordinare,
                       rischio_stockout_prima_di_arrivo, demand_lead, demand_cycle, in_assortimento
                FROM dashboard__reorder_suggestions_top
                ORDER BY rischio_stockout_prima_di_arrivo DESC,
                         qty_da_ordinare DESC,
                         qty_giacenza ASC
                LIMIT :limit
            """),
            {"limit": limit},
        )
        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"reorder-suggestions query failed: {str(e)}")
