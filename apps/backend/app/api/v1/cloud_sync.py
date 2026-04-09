from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Literal

from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db.session import get_db

router = APIRouter(prefix="/api/v1/cloud-sync", tags=["cloud-sync"])


class SyncEnvelope(BaseModel):
    tenant_code: str
    dataset: Literal[
        "dashboard_kpis",
        "sales_daily_family",
        "forecast_summary",
        "reorder_suggestions",
    ]
    records: list[dict[str, Any]] = Field(default_factory=list)
    replace_mode: bool = False


def _get_sync_key(db: Session, tenant_code: str) -> str | None:
    row = db.execute(
        text("""
            select api_key
            from public.greenbrain_sync_api_keys
            where tenant_code = :tenant_code
              and is_active = true
        """),
        {"tenant_code": tenant_code},
    ).mappings().first()
    return row["api_key"] if row else None


def _check_auth(db: Session, tenant_code: str, x_api_key: str | None) -> None:
    if not x_api_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing sync API key",
        )

    expected = _get_sync_key(db, tenant_code)
    if not expected or x_api_key != expected:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid sync API key",
        )


def _touch_runtime_status(db: Session, tenant_code: str, sync_status: str) -> None:
    db.execute(
        text("""
            update public.greenbrain_runtime_connections
            set
              last_sync_at = now(),
              last_sync_status = :sync_status,
              runtime_health = 'healthy'
            where tenant_code = :tenant_code
        """),
        {"tenant_code": tenant_code, "sync_status": sync_status},
    )


@router.get("/health")
def cloud_sync_health():
    return {
        "status": "ok",
        "service": "cloud-sync",
        "ts": datetime.now(timezone.utc).isoformat(),
    }


@router.post("/push")
def push_dataset(
    body: SyncEnvelope,
    x_api_key: str | None = Header(default=None, alias="X-API-Key"),
    db: Session = Depends(get_db),
):
    _check_auth(db, body.tenant_code, x_api_key)

    count = 0

    if body.dataset == "dashboard_kpis":
        if body.replace_mode:
            db.execute(
                text("delete from cloud_sync.dashboard_kpis where tenant_code = :tenant_code"),
                {"tenant_code": body.tenant_code},
            )
        for rec in body.records:
            db.execute(
                text("""
                    insert into cloud_sync.dashboard_kpis
                    (
                      tenant_code, snapshot_ts, sales_7d, sales_ytd,
                      sales_trend_pct, sales_ytd_trend_pct, products_monitored,
                      reorders_week, reorder_risk_lines, reorder_qty_total,
                      source_runtime_ts
                    )
                    values
                    (
                      :tenant_code,
                      coalesce(cast(:snapshot_ts as timestamptz), now()),
                      :sales_7d, :sales_ytd,
                      :sales_trend_pct, :sales_ytd_trend_pct, :products_monitored,
                      :reorders_week, :reorder_risk_lines, :reorder_qty_total,
                      coalesce(cast(:source_runtime_ts as timestamptz), now())
                    )
                """),
                {
                    "tenant_code": body.tenant_code,
                    "snapshot_ts": rec.get("snapshot_ts"),
                    "sales_7d": rec.get("sales_7d"),
                    "sales_ytd": rec.get("sales_ytd"),
                    "sales_trend_pct": rec.get("sales_trend_pct"),
                    "sales_ytd_trend_pct": rec.get("sales_ytd_trend_pct"),
                    "products_monitored": rec.get("products_monitored"),
                    "reorders_week": rec.get("reorders_week"),
                    "reorder_risk_lines": rec.get("reorder_risk_lines"),
                    "reorder_qty_total": rec.get("reorder_qty_total"),
                    "source_runtime_ts": rec.get("source_runtime_ts"),
                },
            )
            count += 1

    elif body.dataset == "sales_daily_family":
        if body.replace_mode:
            db.execute(
                text("delete from cloud_sync.sales_daily_family where tenant_code = :tenant_code"),
                {"tenant_code": body.tenant_code},
            )
        for rec in body.records:
            db.execute(
                text("""
                    insert into cloud_sync.sales_daily_family
                    (
                      tenant_code, sales_date, famiglia, qty,
                      revenue_inc_vat, margin_estimate, source_runtime_ts
                    )
                    values
                    (
                      :tenant_code, cast(:sales_date as date), :famiglia, :qty,
                      :revenue_inc_vat, :margin_estimate,
                      coalesce(cast(:source_runtime_ts as timestamptz), now())
                    )
                    on conflict (tenant_code, sales_date, famiglia)
                    do update set
                      qty = excluded.qty,
                      revenue_inc_vat = excluded.revenue_inc_vat,
                      margin_estimate = excluded.margin_estimate,
                      source_runtime_ts = excluded.source_runtime_ts
                """),
                {
                    "tenant_code": body.tenant_code,
                    "sales_date": rec.get("sales_date"),
                    "famiglia": rec.get("famiglia"),
                    "qty": rec.get("qty"),
                    "revenue_inc_vat": rec.get("revenue_inc_vat"),
                    "margin_estimate": rec.get("margin_estimate"),
                    "source_runtime_ts": rec.get("source_runtime_ts"),
                },
            )
            count += 1

    elif body.dataset == "forecast_summary":
        if body.replace_mode:
            db.execute(
                text("delete from cloud_sync.forecast_summary where tenant_code = :tenant_code"),
                {"tenant_code": body.tenant_code},
            )
        for rec in body.records:
            db.execute(
                text("""
                    insert into cloud_sync.forecast_summary
                    (
                      tenant_code, forecast_date, famiglia, forecast_qty,
                      forecast_revenue_inc_vat, model_name, model_version,
                      confidence_score, source_runtime_ts
                    )
                    values
                    (
                      :tenant_code, cast(:forecast_date as date), :famiglia, :forecast_qty,
                      :forecast_revenue_inc_vat, :model_name, :model_version,
                      :confidence_score,
                      coalesce(cast(:source_runtime_ts as timestamptz), now())
                    )
                    on conflict (tenant_code, forecast_date, famiglia)
                    do update set
                      forecast_qty = excluded.forecast_qty,
                      forecast_revenue_inc_vat = excluded.forecast_revenue_inc_vat,
                      model_name = excluded.model_name,
                      model_version = excluded.model_version,
                      confidence_score = excluded.confidence_score,
                      source_runtime_ts = excluded.source_runtime_ts
                """),
                {
                    "tenant_code": body.tenant_code,
                    "forecast_date": rec.get("forecast_date"),
                    "famiglia": rec.get("famiglia"),
                    "forecast_qty": rec.get("forecast_qty"),
                    "forecast_revenue_inc_vat": rec.get("forecast_revenue_inc_vat"),
                    "model_name": rec.get("model_name"),
                    "model_version": rec.get("model_version"),
                    "confidence_score": rec.get("confidence_score"),
                    "source_runtime_ts": rec.get("source_runtime_ts"),
                },
            )
            count += 1

    elif body.dataset == "reorder_suggestions":
        if body.replace_mode:
            db.execute(
                text("delete from cloud_sync.reorder_suggestions where tenant_code = :tenant_code"),
                {"tenant_code": body.tenant_code},
            )
        for rec in body.records:
            db.execute(
                text("""
                    insert into cloud_sync.reorder_suggestions
                    (
                      tenant_code, suggestion_date, codart, descrizione,
                      famiglia, suggested_qty, urgency, reason, source_runtime_ts
                    )
                    values
                    (
                      :tenant_code, cast(:suggestion_date as date), :codart, :descrizione,
                      :famiglia, :suggested_qty, :urgency, :reason,
                      coalesce(cast(:source_runtime_ts as timestamptz), now())
                    )
                    on conflict (tenant_code, suggestion_date, codart)
                    do update set
                      descrizione = excluded.descrizione,
                      famiglia = excluded.famiglia,
                      suggested_qty = excluded.suggested_qty,
                      urgency = excluded.urgency,
                      reason = excluded.reason,
                      source_runtime_ts = excluded.source_runtime_ts
                """),
                {
                    "tenant_code": body.tenant_code,
                    "suggestion_date": rec.get("suggestion_date"),
                    "codart": rec.get("codart"),
                    "descrizione": rec.get("descrizione"),
                    "famiglia": rec.get("famiglia"),
                    "suggested_qty": rec.get("suggested_qty"),
                    "urgency": rec.get("urgency"),
                    "reason": rec.get("reason"),
                    "source_runtime_ts": rec.get("source_runtime_ts"),
                },
            )
            count += 1

    _touch_runtime_status(db, body.tenant_code, f"push_ok:{body.dataset}:{count}")
    db.commit()

    return {
        "ok": True,
        "tenant_code": body.tenant_code,
        "dataset": body.dataset,
        "processed": count,
    }
