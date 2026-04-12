from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db.session import get_db

router = APIRouter(prefix="/health", tags=["health"])


@router.get("")
def healthcheck():
    return {"status": "ok"}


@router.get("/db")
def healthcheck_db(db: Session = Depends(get_db)):
    result = db.execute(text("SELECT 1 AS ok")).mappings().first()
    return {
        "status": "ok",
        "database": "connected",
        "result": dict(result) if result else None,
    }