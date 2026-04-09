from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db.session import get_db

router = APIRouter(prefix="/api/v1/ops", tags=["ops"])


@router.get("/health")
def ops_health(db: Session = Depends(get_db)):
    checks = {}

    probes = [
        (
            "public.v_ops_pipeline_status",
            "SELECT id, snap_ts, ok FROM public.v_ops_pipeline_status ORDER BY snap_ts DESC LIMIT 1",
        ),
        (
            "ml_ops.v_daily_pipeline_summary_v1",
            "SELECT day, job_type, runs, ok_runs, bad_runs "
            "FROM ml_ops.v_daily_pipeline_summary_v1 "
            "ORDER BY day DESC, job_type ASC LIMIT 5",
        ),
        (
            "public.greenhouse_forecast_results_v2",
            "SELECT 1 FROM public.greenhouse_forecast_results_v2 LIMIT 1",
        ),
    ]

    for label, sql in probes:
        try:
            rows = db.execute(text(sql)).mappings().all()
            checks[label] = {
                "status": "ok",
                "count": len(rows),
                "sample": [dict(r) for r in rows[:3]],
            }
        except Exception as e:
            db.rollback()
            checks[label] = {
                "status": "error",
                "message": str(e),
            }

    overall = "ok" if all(v["status"] == "ok" for v in checks.values()) else "degraded"
    return {"status": overall, "checks": checks}


@router.get("/pipeline-status")
def pipeline_status(
    limit: int = Query(20, ge=1, le=200),
    db: Session = Depends(get_db),
):
    try:
        rows = db.execute(
            text("""
                SELECT
                    run_id,
                    job_type,
                    trigger_mode,
                    status,
                    started_at,
                    finished_at,
                    duration_min,
                    host_name,
                    rows_processed,
                    error_message,
                    git_sha,
                    notes
                FROM ml_ops.v_pipeline_runs_recent_v1
                ORDER BY started_at DESC
                LIMIT :limit
            """),
            {"limit": limit},
        ).mappings().all()

        return {
            "count": len(rows),
            "items": [dict(r) for r in rows],
        }
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"pipeline-status failed: {e}")


@router.get("/family-runs")
def family_runs(
    limit: int = Query(50, ge=1, le=500),
    db: Session = Depends(get_db),
):
    try:
        rows = db.execute(
            text("""
                SELECT
                    family_run_id,
                    pipeline_run_id,
                    job_type,
                    family_name,
                    demand_class_final,
                    model_code,
                    started_at,
                    finished_at,
                    status,
                    rows_written,
                    artifact_path,
                    error_message,
                    error_trace
                FROM ml_ops.family_run_log_v1
                ORDER BY started_at DESC
                LIMIT :limit
            """),
            {"limit": limit},
        ).mappings().all()

        return {
            "count": len(rows),
            "items": [dict(r) for r in rows],
        }
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"family-runs failed: {e}")