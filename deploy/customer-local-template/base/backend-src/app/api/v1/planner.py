import logging
from typing import List, Optional

from fastapi import APIRouter, Depends, Query, HTTPException
from pydantic import BaseModel
from sqlalchemy.exc import ProgrammingError
from sqlalchemy.orm import Session
from sqlalchemy import text

from app.db.session import get_db
from app.api.v1.auth import require_admin

router = APIRouter(prefix="/api/v1/planner", tags=["planner"])


def _rpc_jsonb(db: Session, sql: str, params: dict) -> dict:
    """Call a RETURNS-jsonb RPC and return the inner Python dict.
    psycopg3 deserialises jsonb → dict automatically.
    """
    row = db.execute(text(sql), params).mappings().first()
    if row is None:
        return {}
    val = list(row.values())[0]
    if val is None:
        return {}
    if isinstance(val, dict):
        return val
    import json as _json
    return _json.loads(val) if isinstance(val, str) else {}


class NodeIdsBody(BaseModel):
    node_ids: List[str]


class HeatmapCellsBody(BaseModel):
    mode: str
    node_ids: List[str]


@router.get("/order-suggestions")
def get_order_suggestions(
    famiglia: str = Query(default=None, description="Optional: filter by famiglia"),
    only_to_order: bool = Query(default=False, description="Return only rows with qty_da_ordinare > 0"),
    limit: int = Query(default=200, ge=1, le=1000),
    db: Session = Depends(get_db),
    _: dict = Depends(require_admin),
):
    try:
        base = "SELECT * FROM public.greenhouse_order_suggestions_enriched_v2"
        conditions = []
        params: dict = {"limit": limit}

        if famiglia:
            conditions.append("famiglia = :famiglia")
            params["famiglia"] = famiglia
        if only_to_order:
            conditions.append("qty_da_ordinare > 0")

        where = f" WHERE {' AND '.join(conditions)}" if conditions else ""
        query = text(f"{base}{where} ORDER BY famiglia LIMIT :limit")

        result = db.execute(query, params)
        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"order-suggestions failed: {str(e)}")


@router.get("/space-budget")
def get_space_budget(
    mode: str = Query(..., description="week | roll4"),
    level: str = Query(..., description="famiglia | categoria | fascia"),
    db: Session = Depends(get_db),
    _: dict = Depends(require_admin),
):
    try:
        result = _rpc_jsonb(
            db,
            "SELECT core_planner__get_space_budget(:p_mode, :p_level) AS r",
            {"p_mode": mode, "p_level": level},
        )
        rows = result.get("rows", [])
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"space_budget RPC failed: {str(e)}")


@router.get("/current-week")
def get_current_week(db: Session = Depends(get_db),
    _: dict = Depends(require_admin),):
    try:
        result = _rpc_jsonb(db, "SELECT core_planner__get_current_week52() AS r", {})
        return result  # {"today": ..., "week_52": 12, "iso_year": ..., "week_start": ...}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"current_week52 RPC failed: {str(e)}")


@router.get("/assortment-calendar")
def get_assortment_calendar(
    mode: str = Query(..., description="week | roll4"),
    level: str = Query(..., description="famiglia | categoria | fascia"),
    db: Session = Depends(get_db),
    _: dict = Depends(require_admin),
):
    try:
        result = _rpc_jsonb(
            db,
            "SELECT core_planner__get_assortment_calendar(:p_mode, :p_level) AS r",
            {"p_mode": mode, "p_level": level},
        )
        rows = result.get("rows", [])
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"assortment_calendar RPC failed: {str(e)}")


@router.get("/heatmap-nodes")
def get_heatmap_nodes(
    mode: str = Query(..., description="week | roll4"),
    db: Session = Depends(get_db),
    _: dict = Depends(require_admin),
):
    try:
        result = _rpc_jsonb(
            db,
            "SELECT core_planner__get_heatmap_nodes(:p_mode) AS r",
            {"p_mode": mode},
        )
        nodes = result.get("nodes", [])
        return {"count": len(nodes), "items": nodes}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"heatmap_nodes RPC failed: {str(e)}")


@router.post("/heatmap-week-ranges")
def get_heatmap_week_ranges(body: NodeIdsBody, db: Session = Depends(get_db),
    _: dict = Depends(require_admin),):
    if not body.node_ids:
        return {"count": 0, "items": []}
    try:
        pg_arr = "{" + ",".join(f'"{n}"' for n in body.node_ids) + "}"
        result = _rpc_jsonb(
            db,
            "SELECT core_planner__get_heatmap_week_ranges(CAST(:p_node_ids AS text[])) AS r",
            {"p_node_ids": pg_arr},
        )
        ranges = result.get("ranges", [])
        return {"count": len(ranges), "items": ranges}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"heatmap_week_ranges RPC failed: {str(e)}")


@router.post("/heatmap-roll4-ranges")
def get_heatmap_roll4_ranges(body: NodeIdsBody, db: Session = Depends(get_db),
    _: dict = Depends(require_admin),):
    if not body.node_ids:
        return {"count": 0, "items": []}
    try:
        pg_arr = "{" + ",".join(f'"{n}"' for n in body.node_ids) + "}"
        result = _rpc_jsonb(
            db,
            "SELECT core_planner__get_heatmap_roll4_ranges(CAST(:p_node_ids AS text[])) AS r",
            {"p_node_ids": pg_arr},
        )
        ranges = result.get("ranges", [])
        return {"count": len(ranges), "items": ranges}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"heatmap_roll4_ranges RPC failed: {str(e)}")


@router.post("/heatmap-cells")
def get_heatmap_cells(body: HeatmapCellsBody, db: Session = Depends(get_db),
    _: dict = Depends(require_admin),):
    if not body.node_ids:
        return {"count": 0, "items": []}
    try:
        pg_arr = "{" + ",".join(f'"{n}"' for n in body.node_ids) + "}"
        result = _rpc_jsonb(
            db,
            "SELECT core_planner__get_heatmap_cells(:p_mode, CAST(:p_node_ids AS text[])) AS r",
            {"p_mode": body.mode, "p_node_ids": pg_arr},
        )
        cells = result.get("cells", [])
        return {"count": len(cells), "items": cells}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"heatmap_cells RPC failed: {str(e)}")


@router.get("/assortment-calendar-export")
def get_assortment_calendar_export(
    mode: str = Query(...),
    level: str = Query(...),
    page: int = Query(default=0, ge=0),
    page_size: int = Query(default=8000, ge=1, le=20000),
    db: Session = Depends(get_db),
    _: dict = Depends(require_admin),
):
    try:
        offset = page * page_size
        result = db.execute(
            text("""
                SELECT mode, level, node_id, week_52, state,
                       space_m2_raw, space_share, stock_target, updated_at
                FROM t_core_planner__assortment_calendar
                WHERE mode = :mode AND level = :level
                ORDER BY node_id ASC
                LIMIT :page_size OFFSET :offset
            """),
            {"mode": mode, "level": level, "page_size": page_size, "offset": offset},
        )
        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows, "page": page, "page_size": page_size}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"assortment-calendar-export failed: {str(e)}")


@router.get("/heatmap-week-pivot")
def get_heatmap_week_pivot(
    metric: str = Query(..., description="Metric column name: avg_qty, avg_rev, share_rev, etc."),
    page: int = Query(default=0, ge=0),
    page_size: int = Query(default=1000, ge=1, le=5000),
    db: Session = Depends(get_db),
    _: dict = Depends(require_admin),
):
    allowed = {"avg_qty", "avg_rev", "share_rev", "stock_target", "space_m2"}
    if metric not in allowed:
        raise HTTPException(status_code=400, detail=f"Invalid metric '{metric}'. Use: {', '.join(sorted(allowed))}")
    try:
        offset = page * page_size
        result = db.execute(
            text("SELECT * FROM rpc_heatmap_week_pivot(:metric) LIMIT :page_size OFFSET :offset"),
            {"metric": metric, "page_size": page_size, "offset": offset},
        )
        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows, "page": page, "page_size": page_size}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"heatmap_week_pivot RPC failed: {str(e)}")


@router.get("/calendar-events")
def get_calendar_events(
    date_from: str = Query(..., description="YYYY-MM-DD start of range"),
    date_to: str = Query(..., description="YYYY-MM-DD end of range"),
    db: Session = Depends(get_db),
    _: dict = Depends(require_admin),
):
    logger = logging.getLogger(__name__)
    try:
        result = db.execute(
            text("""
                SELECT id, date, name, impact_level
                FROM calendar_events
                WHERE date >= :date_from
                  AND date <= :date_to
                ORDER BY date ASC
            """),
            {"date_from": date_from, "date_to": date_to},
        )
        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows}
    except ProgrammingError as e:
        if "does not exist" in str(e).lower():
            logger.warning(
                "calendar_events table not found in this DB — "
                "returning empty list (expected in shadow/dev environments)"
            )
            return {"count": 0, "items": []}
        raise HTTPException(status_code=500, detail=f"calendar-events query failed: {str(e)}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"calendar-events query failed: {str(e)}")


@router.get("/assortment")
def get_assortment(
    db: Session = Depends(get_db),
    _: dict = Depends(require_admin),
):
    try:
        result = db.execute(
            text("""
                SELECT
                    famiglia,
                    COUNT(*) AS total_items,
                    SUM(CASE WHEN in_assortimento THEN 1 ELSE 0 END) AS in_assortimento,
                    SUM(CASE WHEN rischio_stockout_prima_di_arrivo THEN 1 ELSE 0 END) AS stockout_risk
                FROM public.greenhouse_order_suggestions_enriched_v2
                GROUP BY famiglia
                ORDER BY stockout_risk DESC, famiglia
            """)
        )
        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"assortment failed: {str(e)}")
