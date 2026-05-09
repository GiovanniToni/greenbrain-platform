from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.api.v1.auth import require_platform_access

router = APIRouter(prefix="/api/v1/catalog", tags=["catalog"])


@router.get("/families")
def list_families(
    limit: int = Query(default=20, ge=1, le=500),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    query = text(
        """
        SELECT famiglia
        FROM public.famiglie_catalog_static
        WHERE famiglia IS NOT NULL
        ORDER BY famiglia
        LIMIT :limit
        """
    )
    rows = db.execute(query, {"limit": limit}).mappings().all()

    return {
        "count": len(rows),
        "items": [dict(row) for row in rows],
    }


@router.get("/search")
def search_catalog(
    term: str = Query(..., min_length=2, description="Search term (min 2 chars)"),
    limit: int = Query(default=50, ge=1, le=500),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        result = db.execute(
            text("SELECT * FROM core_analytics__search_catalog_rich(:term, :limit_n)"),
            {"term": term, "limit_n": limit},
        )
        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"catalog search failed: {str(e)}")


@router.get("/children")
def get_catalog_children(
    level: str = Query(..., description="fascia, categoria, famiglia, fascia_prezzo, articolo"),
    fascia: str = Query(default=None),
    categoria: str = Query(default=None),
    famiglia: str = Query(default=None),
    fascia_prezzo: str = Query(default=None),
    limit: int = Query(default=500, ge=1, le=5000),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        result = db.execute(
            text("""
                SELECT * FROM core_analytics__catalog_children(
                    :p_level, :p_fascia, :p_categoria, :p_famiglia, :p_fascia_prezzo, :p_limit
                )
            """),
            {
                "p_level": level,
                "p_fascia": fascia,
                "p_categoria": categoria,
                "p_famiglia": famiglia,
                "p_fascia_prezzo": fascia_prezzo,
                "p_limit": limit,
            },
        )
        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"catalog_children RPC failed: {str(e)}")


@router.get("/list")
def list_catalog(
    entity_type: str = Query(..., description="famiglia, categoria, fascia, fascia_prezzo, articolo"),
    limit: int = Query(default=500, ge=1, le=5000),
    db: Session = Depends(get_db),
    _: dict = Depends(require_platform_access),
):
    try:
        result = db.execute(
            text("SELECT * FROM core_analytics__list_catalog(:p_entity_type, :p_limit)"),
            {"p_entity_type": entity_type, "p_limit": limit},
        )
        rows = [dict(r._mapping) for r in result]
        return {"count": len(rows), "items": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"catalog list failed: {str(e)}")