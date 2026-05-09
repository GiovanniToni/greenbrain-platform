from typing import List, Optional

from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text

from app.db.session import get_db
from app.api.v1.auth import require_platform_access

router = APIRouter(prefix="/api/v1/analytics", tags=["analytics"])


GRANULARITY_MAP = {
    "day": "daily",
    "week": "weekly",
    "month": "monthly",
    "year": "yearly",
}

ALLOWED_ENTITIES = {"famiglia", "categoria", "fascia", "fascia_prezzo", "articolo"}
BREAKDOWN_ENTITIES = {"famiglia", "categoria", "fascia"}
VALID_NODE_TYPES = {"fascia", "categoria", "famiglia", "fascia_prezzo", "articolo"}


def _sanitise_nodes(tree: any) -> list:
    """Recursively strip null entries and nodes with missing/invalid entity_type.

    The Supabase RPC core_analytics__entity_hierarchy_tree_v1 can return null
    array elements or dicts without entity_type when some hierarchy levels have
    no sales data.  This function normalises the tree before it leaves the API.
    """
    if tree is None:
        return []
    if isinstance(tree, dict):
        tree = [tree]
    if not isinstance(tree, list):
        return []

    clean = []
    for node in tree:
        if not isinstance(node, dict):
            continue
        entity_type = node.get("entity_type")
        if not isinstance(entity_type, str) or not entity_type.strip():
            continue
        children = node.get("children")
        if children is not None:
            node = {**node, "children": _sanitise_nodes(children)}
        clean.append(node)
    return clean


def _resolve_gran(granularity: str) -> str:
    gran = GRANULARITY_MAP.get(granularity)
    if not gran:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid granularity '{granularity}'. Use: day, week, month, year",
        )
    return gran


def _resolve_entity(entity_type: str) -> str:
    if entity_type not in ALLOWED_ENTITIES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid entity_type '{entity_type}'. Use: famiglia, categoria, fascia, fascia_prezzo, articolo",
        )
    return entity_type


def _series_view(gran_db: str, entity_type: str) -> str:
    return f"core_analytics__series_{gran_db}_{entity_type}_lc"


def _breakdown_view(gran_db: str, entity_type: str) -> str:
    return f"core_analytics__breakdown_{gran_db}_{entity_type}_fp_v2"


@router.get("/series")
def get_series(
    entity_type: str = Query(..., description="famiglia, categoria, fascia, fascia_prezzo, articolo"),
    granularity: str = Query(..., description="day, week, month, year"),
    entity_key: str = Query(...),
    date_from: str = Query(...),
    date_to: str = Query(...),
    fascia_prezzo: Optional[str] = Query(default=None, description="FP filter: routes to breakdown view with ILIKE"),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    # Articolo usa le stesse viste gerarchiche degli altri livelli:
    # core_analytics__series_{day/week/month/year}_articolo_lc
    gran = _resolve_gran(granularity)
    _resolve_entity(entity_type)

    try:
        # ---- FASCIA_PREZZO FILTER: breakdown view + ILIKE ----
        if fascia_prezzo and entity_type in BREAKDOWN_ENTITIES:
            view_name = _breakdown_view(gran, entity_type)
            result = db.execute(
                text(f"""
                    SELECT
                        *,
                        qty_venduta AS qty_venduta_tot,
                        qty_forecast AS qty_forecast_tot
                    FROM {view_name}
                    WHERE entity_key_lc = :entity_key
                      AND fascia_prezzo_iva_inc ILIKE :fp
                      AND data >= :date_from
                      AND data <= :date_to
                    ORDER BY data
                """),
                {"entity_key": entity_key, "fp": fascia_prezzo, "date_from": date_from, "date_to": date_to},
            )
        else:
            # ---- NORMAL TOTAL SERIES ----
            view_name = _series_view(gran, entity_type)
            result = db.execute(
                text(f"""
                    SELECT *
                    FROM {view_name}
                    WHERE entity_key_lc = :entity_key
                      AND data >= :date_from
                      AND data <= :date_to
                    ORDER BY data
                """),
                {"entity_key": entity_key, "date_from": date_from, "date_to": date_to},
            )
        rows = [dict(row._mapping) for row in result]
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"series query failed: {str(e)}")


@router.get("/series-breakdown")
def get_series_breakdown(
    entity_type: str = Query(..., description="famiglia, categoria, fascia"),
    granularity: str = Query(..., description="day, week, month, year"),
    entity_key: str = Query(...),
    date_from: str = Query(...),
    date_to: str = Query(...),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    if entity_type not in BREAKDOWN_ENTITIES:
        raise HTTPException(
            status_code=400,
            detail=f"Breakdown not available for entity_type='{entity_type}'. Use: famiglia, categoria, fascia",
        )
    gran = _resolve_gran(granularity)
    try:
        view_name = _breakdown_view(gran, entity_type)
        result = db.execute(
            text(f"""
                SELECT *
                FROM {view_name}
                WHERE entity_key_lc = :entity_key
                  AND data >= :date_from
                  AND data <= :date_to
                ORDER BY data
            """),
            {"entity_key": entity_key, "date_from": date_from, "date_to": date_to},
        )
        rows = [dict(row._mapping) for row in result]
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"series-breakdown query failed: {str(e)}")


@router.get("/range-totals")
def get_range_totals(
    entity_type: str = Query(..., description="famiglia, categoria, fascia, fascia_prezzo"),
    entity_key: str = Query(...),
    date_from: str = Query(...),
    date_to: str = Query(...),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        if entity_type == "articolo":
            result = db.execute(
                text("""
                    WITH days AS (
                        SELECT generate_series(CAST(:p_date_from AS date), CAST(:p_date_to AS date), interval '1 day')::date AS data
                    ),
                    daily AS (
                        SELECT
                            d.data,
                            COALESCE(a.qty, 0)::numeric AS qty,
                            COALESCE(a.imponibile_netto, 0)::numeric AS imp
                        FROM days d
                        LEFT JOIN public.core_analytics__article_sales_daily a
                          ON a.data = d.data
                         AND a.codart = :p_entity_key
                    )
                    SELECT
                        SUM(qty) AS qty_tot,
                        SUM(imp) AS imp_tot,
                        COUNT(*)::int AS days,
                        COUNT(*) FILTER (WHERE qty > 0)::int AS active_days,
                        COUNT(*) FILTER (WHERE qty = 0)::int AS zero_days,
                        (SELECT data FROM daily ORDER BY qty ASC, data ASC LIMIT 1) AS min_day,
                        MIN(qty) AS min_qty,
                        (SELECT data FROM daily ORDER BY qty DESC, data ASC LIMIT 1) AS max_day,
                        MAX(qty) AS max_qty
                    FROM daily
                """),
                {
                    "p_entity_key": entity_key.strip(),
                    "p_date_from": date_from,
                    "p_date_to": date_to,
                },
            )
        else:
            _resolve_entity(entity_type)
            result = db.execute(
                text("""
                    SELECT * FROM core_analytics__range_totals_v2(
                        :p_entity_type, :p_entity_key, :p_date_from, :p_date_to
                    )
                """),
                {
                    "p_entity_type": entity_type,
                    "p_entity_key": entity_key,
                    "p_date_from": date_from,
                    "p_date_to": date_to,
                },
            )
        row = result.mappings().first()
        return dict(row) if row else {}
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"range_totals RPC failed: {str(e)}",
        )


@router.get("/series-bounds")
def get_series_bounds(
    entity_type: str = Query(..., description="famiglia, categoria, fascia, fascia_prezzo"),
    granularity: str = Query(default="day", description="day, week, month, year"),
    entity_key: str = Query(default=None, description="Optional: filter to a specific entity"),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    gran = _resolve_gran(granularity)

    if entity_type == "articolo":
        view_name = "public.core_analytics__article_sales_daily"
        try:
            result = db.execute(
                text("""
                    SELECT
                        MIN(data) AS min_date,
                        MAX(data) AS max_date,
                        COUNT(*) AS total_rows
                    FROM public.core_analytics__article_sales_daily
                    WHERE codart = :entity_key
                """),
                {"entity_key": entity_key.strip() if entity_key else None},
            )
            row = result.mappings().first()
            return {"view": view_name, **(dict(row) if row else {})}
        except Exception as e:
            raise HTTPException(
                status_code=500,
                detail=f"series-bounds failed on '{view_name}': {str(e)}",
            )

    _resolve_entity(entity_type)
    view_name = _series_view(gran, entity_type)

    try:
        if entity_key:
            result = db.execute(
                text(f"""
                    SELECT
                        MIN(data) AS min_date,
                        MAX(data) AS max_date,
                        COUNT(*) AS total_rows
                    FROM {view_name}
                    WHERE entity_key_lc = :entity_key
                """),
                {"entity_key": entity_key},
            )
        else:
            result = db.execute(
                text(f"""
                    SELECT
                        MIN(data) AS min_date,
                        MAX(data) AS max_date,
                        COUNT(DISTINCT entity_key_lc) AS total_entities
                    FROM {view_name}
                """)
            )
        row = result.mappings().first()
        return {"view": view_name, **(dict(row) if row else {})}
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"series-bounds failed on '{view_name}': {str(e)}",
        )


@router.get("/future-windows")
def get_future_windows(
    famiglia: str = Query(default=None, description="Optional: filter by famiglia"),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        if famiglia:
            result = db.execute(
                text("""
                    SELECT
                        data AS forecast_date,
                        COUNT(DISTINCT fascia_prezzo_iva_inc) AS price_bands
                    FROM public.greenhouse_forecast_results_v2
                    WHERE data > CURRENT_DATE AND famiglia = :famiglia
                    GROUP BY data
                    ORDER BY data
                """),
                {"famiglia": famiglia},
            )
        else:
            result = db.execute(
                text("""
                    SELECT
                        data AS forecast_date,
                        COUNT(DISTINCT famiglia) AS families
                    FROM public.greenhouse_forecast_results_v2
                    WHERE data > CURRENT_DATE
                    GROUP BY data
                    ORDER BY data
                """)
            )
        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"future-windows failed: {str(e)}",
        )


@router.get("/compare-series")
def get_compare_series(
    entity_type: str = Query(..., description="famiglia, categoria, fascia"),
    entity_key: str = Query(...),
    date_from: str = Query(...),
    date_to: str = Query(...),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    col_map = {
        "famiglia": "famiglia",
        "categoria": "categoria_corretta",
        "fascia": "fascia_corretta",
    }
    col = col_map.get(entity_type)
    if not col:
        raise HTTPException(
            status_code=400,
            detail=f"entity_type '{entity_type}' not supported for compare-series. Use: famiglia, categoria, fascia",
        )
    try:
        result = db.execute(
            text(f"""
                SELECT data, qty_venduta_tot, qty_forecast_tot
                FROM core_analytics__series_daily_total
                WHERE {col} = :entity_key
                  AND data >= :date_from
                  AND data <= :date_to
                ORDER BY data
            """),
            {"entity_key": entity_key, "date_from": date_from, "date_to": date_to},
        )
        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"compare-series query failed: {str(e)}")


@router.get("/entity-summary")
def get_entity_summary(
    p_entity_type: str = Query(...),
    p_entity_key: str = Query(...),
    p_date_from: str = Query(...),
    p_date_to: str = Query(...),
    p_top_n: int = Query(default=10),
    p_fascia: Optional[str] = Query(default=None),
    p_categoria: Optional[str] = Query(default=None),
    p_famiglia: Optional[str] = Query(default=None),
    p_fascia_prezzo: Optional[str] = Query(default=None),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        result = db.execute(
            text("""
                SELECT * FROM core_analytics__entity_hierarchy_tree_v1(
                    :p_entity_type, :p_entity_key, :p_date_from, :p_date_to,
                    :p_top_n, :p_fascia, :p_categoria, :p_famiglia, :p_fascia_prezzo
                )
            """),
            {
                "p_entity_type": p_entity_type,
                "p_entity_key": p_entity_key,
                "p_date_from": p_date_from,
                "p_date_to": p_date_to,
                "p_top_n": p_top_n,
                "p_fascia": p_fascia,
                "p_categoria": p_categoria,
                "p_famiglia": p_famiglia,
                "p_fascia_prezzo": p_fascia_prezzo,
            },
        )
        row = result.mappings().first()
        if not row:
            return None
        payload = dict(row)
        # core_analytics__entity_hierarchy_tree_v1 returns a single JSONB column
        # whose name is the function name itself.  Unwrap it so callers always
        # receive the flat payload {entity_type, entity_key, totals, tree, ...}.
        if len(payload) == 1:
            inner = next(iter(payload.values()))
            if isinstance(inner, dict):
                payload = inner
        if "tree" in payload:
            payload["tree"] = _sanitise_nodes(payload["tree"])
        return payload
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"entity_hierarchy_tree RPC failed: {str(e)}")


@router.get("/components")
def get_components(
    entity_type: str = Query(..., description="famiglia, categoria, fascia, fascia_prezzo"),
    entity_key: str = Query(...),
    limit: int = Query(default=5000, ge=1, le=10000),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    col_map = {
        "famiglia": "famiglia",
        "categoria": "categoria_corretta",
        "fascia": "fascia_corretta",
        "fascia_prezzo": "fascia_prezzo_iva_inc",
    }
    col = col_map.get(entity_type)
    if not col:
        raise HTTPException(
            status_code=400,
            detail=f"entity_type '{entity_type}' not supported for components. Use: famiglia, categoria, fascia, fascia_prezzo, articolo",
        )
    try:
        result = db.execute(
            text(f"""
                SELECT codart, articolo_nome, pot_size, fascia_prezzo_iva_inc, prezzo_iva_inclusa
                FROM core_analytics__components_articles
                WHERE {col} = :entity_key
                LIMIT :limit
            """),
            {"entity_key": entity_key, "limit": limit},
        )
        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"components query failed: {str(e)}")


@router.get("/seasonality")
def get_seasonality(
    entity_type: str = Query(..., description="famiglia, categoria, fascia, fascia_prezzo, articolo"),
    entity_key: str = Query(...),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        if entity_type == "articolo":
            result = db.execute(
                text("""
                    SELECT month_num, avg_qty_per_day, sum_qty,
                           avg_rev_per_day, sum_rev, n_days
                    FROM public.core_analytics__seasonality_month_articolo_lc
                    WHERE entity_key_lc = lower(trim(:entity_key))
                    ORDER BY month_num
                """),
                {"entity_key": entity_key.strip()},
            )
        else:
            _resolve_entity(entity_type)
            result = db.execute(
                text("""
                    SELECT month_num, avg_qty_per_day, sum_qty,
                           avg_rev_per_day, sum_rev, n_days
                    FROM core_analytics__seasonality_month
                    WHERE entity_type = :entity_type
                      AND entity_key_lc = :entity_key_lc
                    ORDER BY month_num
                """),
                {"entity_type": entity_type, "entity_key_lc": entity_key.strip().lower()},
            )

        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"seasonality query failed: {str(e)}")


@router.get("/seasonality-weekly")
def get_seasonality_weekly(
    entity_type: str = Query(..., description="famiglia, categoria, fascia, fascia_prezzo, articolo"),
    entity_key: str = Query(...),
    fascia_prezzo: Optional[str] = Query(default=None),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    day_names = {
        0: "Dom",
        1: "Lun",
        2: "Mar",
        3: "Mer",
        4: "Gio",
        5: "Ven",
        6: "Sab",
    }

    try:
        if entity_type == "articolo":
            result = db.execute(
                text("""
                    SELECT
                        extract(dow from data)::int AS dow,
                        avg(qty_venduta)::numeric AS avg_qty_per_day,
                        sum(qty_venduta)::numeric AS sum_qty,
                        avg(imponibile_netto)::numeric AS avg_rev_per_day,
                        sum(imponibile_netto)::numeric AS sum_rev,
                        count(distinct data)::int AS n_days
                    FROM public.core_analytics__article_sales_daily
                    WHERE lower(trim(codart)) = lower(trim(:entity_key))
                    GROUP BY 1
                    ORDER BY 1
                """),
                {"entity_key": entity_key.strip()},
            )

        elif fascia_prezzo and entity_type == "famiglia":
            view_name = "public.core_analytics__breakdown_daily_famiglia_fp_v2"
            result = db.execute(
                text(f"""
                    SELECT
                        extract(dow from data)::int AS dow,
                        avg(qty_venduta)::numeric AS avg_qty_per_day,
                        sum(qty_venduta)::numeric AS sum_qty,
                        avg(imponibile_netto_tot)::numeric AS avg_rev_per_day,
                        sum(imponibile_netto_tot)::numeric AS sum_rev,
                        count(distinct data)::int AS n_days
                    FROM {view_name}
                    WHERE entity_key_lc = lower(trim(:entity_key))
                      AND fascia_prezzo_iva_inc = :fascia_prezzo
                    GROUP BY 1
                    ORDER BY 1
                """),
                {
                    "entity_key": entity_key.strip(),
                    "fascia_prezzo": fascia_prezzo.strip(),
                },
            )

        elif fascia_prezzo and entity_type in ("categoria", "fascia"):
            raise HTTPException(
                status_code=400,
                detail="fascia_prezzo è supportata solo insieme a entity_type=famiglia",
            )

        else:
            _resolve_entity(entity_type)
            view_map = {
                "famiglia": "public.core_analytics__series_daily_famiglia_lc",
                "categoria": "public.core_analytics__series_daily_categoria_lc",
                "fascia": "public.core_analytics__series_daily_fascia_lc",
                "fascia_prezzo": "public.core_analytics__series_daily_fascia_prezzo_lc",
            }
            view_name = view_map.get(entity_type)
            if not view_name:
                raise HTTPException(status_code=400, detail=f"entity_type '{entity_type}' non supportato")

            result = db.execute(
                text(f"""
                    SELECT
                        dow::int AS dow,
                        avg(qty_venduta_tot)::numeric AS avg_qty_per_day,
                        sum(qty_venduta_tot)::numeric AS sum_qty,
                        avg(imponibile_netto_tot)::numeric AS avg_rev_per_day,
                        sum(imponibile_netto_tot)::numeric AS sum_rev,
                        count(distinct data)::int AS n_days
                    FROM {view_name}
                    WHERE entity_key_lc = lower(trim(:entity_key))
                    GROUP BY 1
                    ORDER BY 1
                """),
                {"entity_key": entity_key.strip()},
            )

        raw = [dict(r._mapping) for r in result]
        by_dow = {int(r["dow"]): r for r in raw if r.get("dow") is not None}

        rows = []
        for dow in range(7):
            r = by_dow.get(dow)
            rows.append({
                "dow": dow,
                "day_name": day_names[dow],
                "avg_qty_per_day": r["avg_qty_per_day"] if r else 0,
                "sum_qty": r["sum_qty"] if r else 0,
                "avg_rev_per_day": r["avg_rev_per_day"] if r else 0,
                "sum_rev": r["sum_rev"] if r else 0,
                "n_days": r["n_days"] if r else 0,
            })

        return {"count": len(rows), "items": rows}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"seasonality-weekly query failed: {str(e)}")


@router.get("/stock-and-reorder")
def get_stock_and_reorder(
    entity_type: str = Query(...),
    entity_key: str = Query(...),
    fascia_prezzo: Optional[str] = Query(default=None),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    _resolve_entity(entity_type)
    try:
        result = db.execute(
            text("""
                SELECT * FROM core_analytics__stock_and_reorder_v1(
                    :p_entity_type, :p_entity_key, :p_fascia_prezzo
                )
            """),
            {
                "p_entity_type": entity_type,
                "p_entity_key": entity_key,
                "p_fascia_prezzo": fascia_prezzo,
            },
        )
        row = result.mappings().first()
        return dict(row) if row else {}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"stock_and_reorder RPC failed: {str(e)}")


@router.get("/future-windows-stats")
def get_future_windows_stats(
    entity_type: str = Query(..., description="famiglia, categoria, fascia, fascia_prezzo"),
    entity_key: str = Query(...),
    anchor_to: str = Query(..., description="YYYY-MM-DD anchor date"),
    windows: List[int] = Query(default=[7, 14, 30, 60], description="Window sizes in days"),
    fascia_prezzo: Optional[str] = Query(default=None),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    _resolve_entity(entity_type)
    windows_pg = "{" + ",".join(str(w) for w in windows) + "}"
    try:
        if entity_type == "famiglia" and fascia_prezzo:
            result = db.execute(
                text("""
                    WITH w AS (
                        SELECT unnest(CAST(:p_windows AS int[])) AS window_days
                    ),
                    years AS (
                        SELECT generate_series(
                            EXTRACT(YEAR FROM CAST(:p_anchor_to AS date))::int - 20,
                            EXTRACT(YEAR FROM CAST(:p_anchor_to AS date))::int - 1
                        ) AS y
                    ),
                    starts AS (
                        SELECT
                            y,
                            (
                                make_date(
                                    y,
                                    EXTRACT(MONTH FROM CAST(:p_anchor_to AS date))::int,
                                    1
                                )
                                + (
                                    LEAST(
                                        EXTRACT(DAY FROM CAST(:p_anchor_to AS date))::int,
                                        EXTRACT(DAY FROM (
                                            date_trunc(
                                                'month',
                                                make_date(
                                                    y,
                                                    EXTRACT(MONTH FROM CAST(:p_anchor_to AS date))::int,
                                                    1
                                                )
                                            ) + interval '1 month - 1 day'
                                        ))::int
                                    ) - 1
                                ) * interval '1 day'
                            )::date AS start_date
                        FROM years
                    ),
                    samples AS (
                        SELECT
                            w.window_days,
                            s.y,
                            COALESCE(SUM(t.qty_venduta), 0)::numeric AS qty
                        FROM w
                        CROSS JOIN starts s
                        LEFT JOIN public.core_analytics__breakdown_daily_famiglia_fp_v2 t
                          ON t.entity_key_lc = lower(trim(:p_entity_key))
                         AND t.fascia_prezzo_iva_inc = :p_fascia_prezzo
                         AND t.data > s.start_date
                         AND t.data <= s.start_date + (w.window_days * interval '1 day')
                        GROUP BY w.window_days, s.y
                    )
                    SELECT
                        window_days,
                        MIN(qty) AS min_qty,
                        MAX(qty) AS max_qty,
                        AVG(qty) AS avg_qty
                    FROM samples
                    GROUP BY window_days
                    ORDER BY window_days
                """),
                {
                    "p_entity_key": entity_key.strip(),
                    "p_fascia_prezzo": fascia_prezzo,
                    "p_anchor_to": anchor_to,
                    "p_windows": windows_pg,
                },
            )
        else:
            result = db.execute(
                text("""
                    SELECT * FROM core_analytics__future_window_stats_v2(
                        :p_entity_type, :p_entity_key, :p_anchor_to, CAST(:p_windows AS int[])
                    )
                """),
                {
                    "p_entity_type": entity_type,
                    "p_entity_key": entity_key,
                    "p_anchor_to": anchor_to,
                    "p_windows": windows_pg,
                },
            )
        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"future_window_stats RPC failed: {str(e)}",
        )