from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import get_db

router = APIRouter(prefix="/api/v1/system", tags=["system"])


@router.get("/info")
def system_info():
    return {
        "app_name": settings.app_name,
        "environment": settings.app_env,
        "backend_status": "running",
        "api_version": "v1",
    }


@router.get("/db-info")
def system_db_info(db: Session = Depends(get_db)):
    version = db.execute(text("SELECT version() AS version")).mappings().first()
    current_db = db.execute(text("SELECT current_database() AS db")).mappings().first()

    return {
        "database_connected": True,
        "database_name": current_db["db"] if current_db else None,
        "postgres_version": version["version"] if version else None,
    }