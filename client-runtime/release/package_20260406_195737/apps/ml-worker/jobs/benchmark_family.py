#!/usr/bin/env python3
"""
benchmark_family.py — Offline benchmark dei modelli forecast per famiglia.

SAFETY GUARANTEES:
  ✓ NON modifica family_model_assignment_v1 (assignment attivo immutato)
  ✓ NON scrive previsioni di produzione
  ✓ NON scrive in models_v4 (zero file I/O su bundle di produzione)
  ✓ Può solo scrivere in family_model_benchmark_v1 e suggestion_benchmark_v1
  ✓ Rispetta is_locked (suggerisce ma non applica mai)

Azioni:
  benchmark-one-family     --family NOME [--holdout-days N] [--models M1,M2] [--dry-run]
  benchmark-many-families  --families N1,N2,... [--holdout-days N] [--models M1,M2] [--dry-run]
  benchmark-new-families   [--holdout-days N] [--min-days-since N] [--dry-run]
  benchmark-all-families   [--holdout-days N] [--dry-run] [--yes]

Metriche:
  Primaria : WMAPE  (Weighted Mean Absolute Percentage Error)
  Secondarie: MAE, RMSE, BIAS

Soglie suggestion_strength:
  improvement_pct >= 10%: 'strong'
  improvement_pct >=  3%: 'moderate'
  improvement_pct >=  0%: 'weak'
  improvement_pct <   0%: 'regression'
"""
from __future__ import annotations

import os
import sys
import argparse
import warnings
from typing import Optional

import numpy as np
import pandas as pd
import sqlalchemy as sa
from sqlalchemy.engine import URL
from dotenv import load_dotenv

load_dotenv("/opt/greenbrain-platform/client-runtime/etl/.env.ml.runtime")

REPO_DIR = os.getenv("GH_REPO_DIR", "/opt/greenbrain-platform/apps/ml-worker")
sys.path.insert(0, REPO_DIR)

from data_access_v1 import load_family_df_parquet_or_db, safe_slug  # noqa: E402

# Importa le funzioni interne degli engine (offline, nessun file I/O)
from jobs.engines.engine_ets import _fit_forecasts as _ets_fit  # noqa: E402
from jobs.engines.engine_sarima import _fit_forecasts as _sarima_fit  # noqa: E402
from jobs.engines.engine_croston import _croston_sba as _croston_sba_fn  # noqa: E402
from jobs.engines.engine_tsb import _tsb as _tsb_fn  # noqa: E402
from jobs.engines.engine_seasonal_croston import (  # noqa: E402
    _croston_sba as _sc_sba_fn,
    _compute_monthly_factors as _sc_monthly_fn,
)

MIN_DATE = os.getenv("V4_MIN_DATE", "2009-01-01")
DEFAULT_HOLDOUT_DAYS      = 10
MIN_TRAIN_ROWS            = 20    # punti minimi per un backtest significativo
DEFAULT_SUGGESTION_THRESH = 3.0   # % improvement minimo per suggestion 'moderate'
DEFAULT_MIN_DAYS_SINCE    = 30    # giorni senza benchmark per famiglia "nuova"

# Soglie qualità holdout — anti-false-positive sulla suggestion layer
# Configurabili via ENV per ambienti diversi
GLOBAL_MIN_HOLDOUT_SUM       = float(os.getenv("BM_MIN_HOLDOUT_SUM",        "1.0"))  # almeno 1 unità venduta
GLOBAL_MIN_HOLDOUT_NZ_STRONG = int(os.getenv("BM_MIN_HOLDOUT_NZ_STRONG",  "2"))    # min giorni non-zero per strong/moderate
# NAIVE_ZERO — 3 livelli di qualità holdout (C.2)
# strong   → nz >= NZ_STRONG_MIN_NZ  AND sum >= NZ_MODERATE_MAX_SUM
# moderate → nz == 2                  OR  sum in [NZ_WEAK_MAX_SUM, NZ_MODERATE_MAX_SUM)
# weak     → nz == 1                  OR  sum <  NZ_WEAK_MAX_SUM
# suppress → nz == 0                  OR  sum <  GLOBAL_MIN_HOLDOUT_SUM  (gestito globalmente)
NZ_WEAK_MAX_SUM     = float(os.getenv("BM_NZ_WEAK_MAX_SUM",     "3.0"))  # sum < questo → cap weak
NZ_MODERATE_MAX_SUM = float(os.getenv("BM_NZ_MODERATE_MAX_SUM", "5.0"))  # sum < questo (e nz>=2) → cap moderate
NZ_STRONG_MIN_NZ    = int(os.getenv("BM_NZ_STRONG_MIN_NZ",    "3"))     # nz < questo → non può essere strong


# ──────────────────────────────────────────────
# DB helpers
# ──────────────────────────────────────────────

def _get_db_engine():
    dburl = os.getenv("DATABASE_URL")
    if dburl:
        return sa.create_engine(dburl, pool_pre_ping=True)
    url = URL.create(
        "postgresql+psycopg",
        username=os.getenv("PG_USER"),
        password=os.getenv("PG_PASSWORD"),
        host=os.getenv("PG_HOST"),
        port=int(os.getenv("PG_PORT", "5432")),
        database=os.getenv("PG_DB", "postgres"),
        query={"sslmode": os.getenv("PG_SSLMODE", "require")},
    )
    return sa.create_engine(url, pool_pre_ping=True)


# ──────────────────────────────────────────────
# Caricamento serie storica
# ──────────────────────────────────────────────

def _load_daily_series(db_engine, family_name: str) -> pd.Series:
    """Carica la serie storica giornaliera aggregata dal parquet (o DB fallback)."""
    slug = safe_slug(family_name)
    df = load_family_df_parquet_or_db(
        db_engine,
        famiglia=family_name,
        min_date=MIN_DATE,
        famiglia_slug=slug,
    )
    if df.empty:
        return pd.Series(dtype=float)
    df["data"] = pd.to_datetime(df["data"], errors="coerce")
    df["qty_venduta"] = (
        pd.to_numeric(df["qty_venduta"], errors="coerce")
        .fillna(0.0)
        .clip(lower=0.0)
    )
    daily = df.groupby("data")["qty_venduta"].sum().sort_index()
    if daily.empty:
        return pd.Series(dtype=float)
    return daily.asfreq("D", fill_value=0.0)


# ──────────────────────────────────────────────
# Offline fit-predict per engine (zero file I/O)
# ──────────────────────────────────────────────

def _offline_predict(
    model_code: str,
    train_series: pd.Series,
    holdout_days: int,
    holdout_dates: pd.DatetimeIndex,
) -> Optional[list[float]]:
    """
    Fit sul train_series, predice holdout_days valori.
    Restituisce None se il modello non supporta backtest o la serie è troppo corta.
    NON scrive nulla su disco o DB.
    """
    n = len(train_series)
    if n < MIN_TRAIN_ROWS:
        return None

    y_arr = train_series.values  # np.ndarray per engine array-based

    if model_code == "ETS_DAMPED":
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            return _ets_fit(train_series, holdout_days)

    elif model_code == "SARIMA":
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            return _sarima_fit(train_series, holdout_days)

    elif model_code == "CROSTON_SBA":
        alpha = float(os.getenv("CROSTON_ALPHA", "0.1"))
        rate  = _croston_sba_fn(y_arr, alpha)
        return [max(0.0, rate)] * holdout_days

    elif model_code == "TSB":
        alpha = float(os.getenv("TSB_ALPHA", "0.1"))
        beta  = float(os.getenv("TSB_BETA",  "0.1"))
        prob, size = _tsb_fn(y_arr, alpha, beta)
        rate = max(0.0, prob * size)
        return [rate] * holdout_days

    elif model_code == "SEASONAL_CROSTON_SBA":
        alpha      = float(os.getenv("SEASONAL_CROSTON_ALPHA",      "0.1"))
        min_months = int(os.getenv("SEASONAL_CROSTON_MIN_MONTHS", "12"))
        rate       = _sc_sba_fn(y_arr, alpha)
        factors, _ = _sc_monthly_fn(train_series, min_months)
        return [max(0.0, rate * factors.get(d.month, 1.0)) for d in holdout_dates]

    elif model_code == "NAIVE_ZERO":
        return [0.0] * holdout_days

    else:
        # V4_TWEEDIE_BUNDLE e sconosciuti: non benchmarkabili inline
        return None


# ──────────────────────────────────────────────
# Metriche
# ──────────────────────────────────────────────

def _compute_metrics(actual: np.ndarray, pred: np.ndarray) -> dict:
    """Calcola WMAPE (primaria), MAE, RMSE, BIAS."""
    n = len(actual)
    if n == 0:
        return {"wmape": None, "mae": None, "rmse": None, "bias": None}

    pred_arr   = np.asarray(pred,   dtype=float)
    actual_arr = np.asarray(actual, dtype=float)
    errors     = pred_arr - actual_arr
    abs_errors = np.abs(errors)
    total      = actual_arr.sum()

    if total <= 0.0:
        wmape = 0.0 if pred_arr.sum() == 0.0 else 100.0
    else:
        wmape = float(abs_errors.sum() / total * 100.0)

    return {
        "wmape": round(wmape,                                    4),
        "mae":   round(float(abs_errors.mean()),                 4),
        "rmse":  round(float(np.sqrt((errors ** 2).mean())),     4),
        "bias":  round(float(errors.mean()),                     4),
    }


def _suggestion_strength(improvement_pct: Optional[float]) -> str:
    if improvement_pct is None:
        return "unknown"
    if improvement_pct >= 10.0:
        return "strong"
    if improvement_pct >= DEFAULT_SUGGESTION_THRESH:
        return "moderate"
    if improvement_pct >= 0.0:
        return "weak"
    return "regression"


# Rank numerico per confrontare e cappare i livelli di strength
_STRENGTH_RANK: dict[str, int] = {"strong": 3, "moderate": 2, "weak": 1, "regression": 0, "unknown": 0}


# ──────────────────────────────────────────────
# Core benchmark per singola famiglia
# ──────────────────────────────────────────────

def _benchmark_family(
    db_engine,
    family_name: str,
    holdout_days: int,
    model_codes: list[str],
) -> dict:
    """
    Esegue il benchmark offline per una famiglia.
    Restituisce un dict con results (list) e best_model_code.
    """
    series = _load_daily_series(db_engine, family_name)
    min_total = holdout_days + MIN_TRAIN_ROWS

    if len(series) < min_total:
        return {
            "family_name":     family_name,
            "status":          "skipped",
            "reason":          f"storia troppo corta ({len(series)} giorni, min {min_total})",
            "results":         [],
            "best_model_code": None,
            "holdout_days":    holdout_days,
        }

    train_series  = series.iloc[:-holdout_days]
    test_series   = series.iloc[-holdout_days:]
    holdout_dates = test_series.index
    actual        = test_series.values

    holdout_sum_actual    = float(actual.sum())
    holdout_nonzero_days  = int((actual > 0).sum())
    training_sum_actual   = float(train_series.values.sum())
    training_nonzero_days = int((train_series.values > 0).sum())

    results: list[dict] = []
    for mc in model_codes:
        try:
            pred = _offline_predict(mc, train_series, holdout_days, holdout_dates)
            if pred is None:
                results.append({
                    "model_code": mc,
                    "status":     "skipped",
                    "wmape": None, "mae": None, "rmse": None, "bias": None,
                    "notes": "supports_backtest=FALSE o serie troppo corta",
                })
                continue

            metrics = _compute_metrics(actual, pred)
            results.append({
                "model_code":    mc,
                "status":        "ok",
                "train_rows":    len(train_series),
                "test_rows":     holdout_days,
                "holdout_start": str(holdout_dates[0].date()),
                "holdout_end":   str(holdout_dates[-1].date()),
                **metrics,
                "notes": None,
            })
        except Exception as exc:
            results.append({
                "model_code": mc,
                "status":     "error",
                "wmape": None, "mae": None, "rmse": None, "bias": None,
                "notes": str(exc)[:300],
            })

    # Individua best model (WMAPE minimo tra risultati validi)
    valid = [r for r in results if r["status"] == "ok" and r["wmape"] is not None]
    best_model_code = None
    if valid:
        best = min(valid, key=lambda r: r["wmape"])
        best_model_code = best["model_code"]

    for r in results:
        r["is_best"] = (
            r["model_code"] == best_model_code
            and r["status"] == "ok"
        )

    return {
        "family_name":          family_name,
        "status":               "ok",
        "holdout_days":         holdout_days,
        "series_len":           len(series),
        "results":              results,
        "best_model_code":      best_model_code,
        "holdout_sum_actual":   holdout_sum_actual,
        "holdout_nonzero_days": holdout_nonzero_days,
        "training_sum_actual":  training_sum_actual,
        "training_nonzero_days": training_nonzero_days,
    }


# ──────────────────────────────────────────────
# Scrittura DB
# ──────────────────────────────────────────────

def _create_benchmark_run(conn, scope: str, scope_detail: str, holdout_days: int) -> int:
    row = conn.execute(sa.text("""
        INSERT INTO ml_forecast.family_benchmark_run_v1
            (triggered_by, scope, scope_detail, holdout_days, status)
        VALUES ('manual', :sc, :sd, :hd, 'running')
        RETURNING run_id
    """), {"sc": scope, "sd": scope_detail, "hd": holdout_days}).first()
    return int(row[0])


def _close_benchmark_run(
    conn, run_id: int, status: str,
    families_done: int, models_tested: int,
    error_msg: Optional[str] = None,
):
    conn.execute(sa.text("""
        UPDATE ml_forecast.family_benchmark_run_v1
        SET status        = :st,
            finished_at   = now(),
            families_done = :fd,
            models_tested = :mt,
            error_message = :em
        WHERE run_id = :rid
    """), {"st": status, "fd": families_done, "mt": models_tested,
           "em": error_msg, "rid": run_id})


def _write_family_results(conn, family_result: dict, run_id: int):
    """Scrive i risultati di una famiglia in family_model_benchmark_v1."""
    for r in family_result["results"]:
        conn.execute(sa.text("""
            INSERT INTO ml_forecast.family_model_benchmark_v1
                (run_id, family_name, model_code, holdout_days,
                 holdout_start, holdout_end, train_rows, test_rows,
                 wmape, mae, rmse, bias, is_best,
                 holdout_sum_actual, holdout_nonzero_days,
                 training_sum_actual, training_nonzero_days,
                 notes)
            VALUES
                (:rid, :fn, :mc, :hd,
                 :hs, :he, :tr, :te,
                 :wm, :ma, :rm, :bi, :ib,
                 :hsa, :hnd, :tsa, :tnd,
                 :nt)
            ON CONFLICT (run_id, family_name, model_code) DO UPDATE SET
                wmape                 = EXCLUDED.wmape,
                mae                   = EXCLUDED.mae,
                rmse                  = EXCLUDED.rmse,
                bias                  = EXCLUDED.bias,
                is_best               = EXCLUDED.is_best,
                holdout_sum_actual    = EXCLUDED.holdout_sum_actual,
                holdout_nonzero_days  = EXCLUDED.holdout_nonzero_days,
                training_sum_actual   = EXCLUDED.training_sum_actual,
                training_nonzero_days = EXCLUDED.training_nonzero_days,
                notes                 = EXCLUDED.notes
        """), {
            "rid": run_id,
            "fn":  family_result["family_name"],
            "mc":  r["model_code"],
            "hd":  family_result.get("holdout_days", 10),
            "hs":  r.get("holdout_start"),
            "he":  r.get("holdout_end"),
            "tr":  r.get("train_rows"),
            "te":  r.get("test_rows"),
            "wm":  r.get("wmape"),
            "ma":  r.get("mae"),
            "rm":  r.get("rmse"),
            "bi":  r.get("bias"),
            "ib":  r.get("is_best", False),
            "hsa": family_result.get("holdout_sum_actual"),
            "hnd": family_result.get("holdout_nonzero_days"),
            "tsa": family_result.get("training_sum_actual"),
            "tnd": family_result.get("training_nonzero_days"),
            "nt":  r.get("notes"),
        })


def _write_suggestion(
    conn,
    family_result: dict,
    run_id: int,
    assigned_model: Optional[str],
    threshold_pct: float,
) -> str:
    """
    Scrive o aggiorna suggestion via UPSERT (ON CONFLICT DO UPDATE).
    Applica filtri qualità holdout anti-false-positive.
    NON tocca family_model_assignment_v1.

    Returns:
        'already_optimal'          — best model == assigned, nessuna azione
        'suppressed_no_best'       — nessun best model disponibile
        'suppressed_no_metrics'    — best model senza metriche valide
        'suppressed_sparse_holdout'— holdout completamente vuoto (sum < soglia)
        'created'                  — nuova suggestion inserita
        'updated'                  — suggestion esistente aggiornata (UPSERT)
    """
    best_mc = family_result.get("best_model_code")
    if not best_mc:
        return "suppressed_no_best"

    if best_mc == assigned_model:
        return "already_optimal"

    holdout_sum = family_result.get("holdout_sum_actual", 0.0) or 0.0
    holdout_nz  = family_result.get("holdout_nonzero_days", 0) or 0

    # FILTRO GLOBALE: holdout completamente vuoto → nessuna suggestion affidabile
    # Qualunque modello che predice 0 vince su holdout vuoto: non è informativo.
    # Aggiorna comunque la suggestion aperta esistente con suppression_reason
    # (evita che vecchie suggestion 'strong' rimangano senza contesto).
    if holdout_sum < GLOBAL_MIN_HOLDOUT_SUM or holdout_nz == 0:
        reason = f"suppressed_sparse_holdout(sum={holdout_sum:.1f},nz={holdout_nz})"    
        conn.execute(sa.text("""
            UPDATE ml_forecast.family_model_suggestion_benchmark_v1
            SET suppression_reason = :sr,
                benchmark_run_id   = :rid,
                notes              = :nt
            WHERE family_name  = :fn
              AND is_applied    = FALSE
              AND suppression_reason IS DISTINCT FROM :sr
        """), {
            "fn":  family_result["family_name"],
            "sr":  reason,
            "rid": run_id,
            "nt":  f"suppressed by run_id={run_id}",
        })
        return reason

    best_r = next(
        (r for r in family_result["results"]
         if r["model_code"] == best_mc and r["status"] == "ok"),
        None,
    )
    if not best_r:
        return "suppressed_no_metrics"

    assigned_r = next(
        (r for r in family_result["results"]
         if r["model_code"] == assigned_model and r["status"] == "ok"),
        None,
    )

    best_wmape     = best_r["wmape"]
    assigned_wmape = assigned_r["wmape"] if assigned_r else None

    if assigned_wmape is not None and assigned_wmape > 0:
        improvement_pct = round(
            (assigned_wmape - best_wmape) / assigned_wmape * 100.0, 2
        )
    else:
        improvement_pct = None

    strength = _suggestion_strength(improvement_pct)
    suppression_reason: Optional[str] = None

    # FILTRO HOLDOUT DEBOLE: pochi giorni non-zero → downgrade a weak
    # Evita strong/moderate su holdout sparso (es. 1 giorno non-zero su 10)
    if holdout_nz < GLOBAL_MIN_HOLDOUT_NZ_STRONG and strength in ("strong", "moderate"):
        strength = "weak"
        suppression_reason = (
            f"downgraded:holdout_nz_days={holdout_nz}<{GLOBAL_MIN_HOLDOUT_NZ_STRONG}"
        )

    # FILTRO NAIVE_ZERO C.2 — 3 livelli di qualità holdout
    # NAIVE_ZERO vince sempre su holdout sparso: serve un holdout solido per
    # promuovere suggestion forti. Regole in ordine decrescente di restrizione:
    #   weak cap     : nz == 1  OR  sum < NZ_WEAK_MAX_SUM
    #   moderate cap : nz  < NZ_STRONG_MIN_NZ  OR  sum < NZ_MODERATE_MAX_SUM
    #   no cap       : nz >= NZ_STRONG_MIN_NZ  AND sum >= NZ_MODERATE_MAX_SUM
    if best_mc == "NAIVE_ZERO":
        nz_parts: list[str] = []
        nz_cap: Optional[str] = None

        if holdout_nz == 1 or holdout_sum < NZ_WEAK_MAX_SUM:
            nz_cap = "weak"
            if holdout_nz == 1:
                nz_parts.append(f"holdout_nz=1")
            if holdout_sum < NZ_WEAK_MAX_SUM:
                nz_parts.append(f"holdout_sum={holdout_sum:.1f}<{NZ_WEAK_MAX_SUM}")
        elif holdout_nz < NZ_STRONG_MIN_NZ or holdout_sum < NZ_MODERATE_MAX_SUM:
            nz_cap = "moderate"
            if holdout_nz < NZ_STRONG_MIN_NZ:
                nz_parts.append(f"holdout_nz={holdout_nz}<{NZ_STRONG_MIN_NZ}")
            if holdout_sum < NZ_MODERATE_MAX_SUM:
                nz_parts.append(f"holdout_sum={holdout_sum:.1f}<{NZ_MODERATE_MAX_SUM}")

        if nz_cap is not None and _STRENGTH_RANK.get(strength, 0) > _STRENGTH_RANK.get(nz_cap, 0):
            reason = f"naive_zero_cap_{nz_cap}:" + "|".join(nz_parts)
            strength = nz_cap
            suppression_reason = (
                reason if suppression_reason is None
                else suppression_reason + "|" + reason
            )

    # UPSERT: 1 suggestion aperta per famiglia (ux_suggestion_one_open_per_family)
    # ON CONFLICT aggiorna la suggestion esistente con i nuovi dati del run corrente.
    row = conn.execute(sa.text("""
        INSERT INTO ml_forecast.family_model_suggestion_benchmark_v1
            (family_name, model_code, benchmark_run_id,
             error_metric, error_value,
             competitor_model_code, competitor_error_value,
             improvement_pct, is_best, suggestion_strength,
             min_improvement_threshold, suppression_reason, notes)
        VALUES
            (:fn, :mc, :rid,
             'WMAPE', :ev,
             :cmc, :cev,
             :imp, TRUE, :str,
             :thr, :sr, :nt)
        ON CONFLICT (family_name)
        WHERE (is_applied = FALSE)
        DO UPDATE SET
            model_code               = EXCLUDED.model_code,
            benchmark_run_id         = EXCLUDED.benchmark_run_id,
            error_value              = EXCLUDED.error_value,
            competitor_model_code    = EXCLUDED.competitor_model_code,
            competitor_error_value   = EXCLUDED.competitor_error_value,
            improvement_pct          = EXCLUDED.improvement_pct,
            suggestion_strength      = EXCLUDED.suggestion_strength,
            suppression_reason       = EXCLUDED.suppression_reason,
            suggested_at             = now(),
            notes                    = EXCLUDED.notes
        RETURNING (xmax::text::bigint = 0) AS was_inserted
    """), {
        "fn":  family_result["family_name"],
        "mc":  best_mc,
        "rid": run_id,
        "ev":  best_wmape,
        "cmc": assigned_model,
        "cev": assigned_wmape,
        "imp": improvement_pct,
        "str": strength,
        "thr": threshold_pct,
        "sr":  suppression_reason,
        "nt":  f"run_id={run_id}",
    })
    was_inserted = row.scalar()
    return "created" if was_inserted else "updated"


# ──────────────────────────────────────────────
# Helpers queries
# ──────────────────────────────────────────────

def _get_benchmark_models(conn) -> list[str]:
    """Restituisce i model_code abilitati al benchmark con supports_backtest=TRUE."""
    rows = conn.execute(sa.text("""
        SELECT model_code
        FROM ml_forecast.model_catalog_v1
        WHERE COALESCE(benchmark_enabled, TRUE) = TRUE
          AND COALESCE(supports_backtest,  TRUE) = TRUE
          AND COALESCE(is_active,          TRUE) = TRUE
        ORDER BY COALESCE(model_priority, 99), model_code
    """)).fetchall()
    return [r[0] for r in rows]


def _get_active_families(conn) -> list[tuple[str, Optional[str]]]:
    rows = conn.execute(sa.text("""
        SELECT s.family_name, a.model_code
        FROM ml_forecast.family_model_state_v1       s
        LEFT JOIN ml_forecast.family_model_assignment_v1 a ON a.family_name = s.family_name
        WHERE s.is_active = TRUE
        ORDER BY s.family_name
    """)).fetchall()
    return [(r[0], r[1]) for r in rows]


def _get_new_families(conn, min_days_since: int) -> list[tuple[str, Optional[str]]]:
    rows = conn.execute(sa.text("""
        SELECT s.family_name, a.model_code
        FROM ml_forecast.family_model_state_v1       s
        LEFT JOIN ml_forecast.family_model_assignment_v1 a ON a.family_name = s.family_name
        WHERE s.is_active = TRUE
          AND NOT EXISTS (
              SELECT 1 FROM ml_forecast.family_model_benchmark_v1 b
              WHERE b.family_name = s.family_name
                AND b.competed_at >= now() - (:days || ' days')::INTERVAL
          )
        ORDER BY s.family_name
    """), {"days": min_days_since}).fetchall()
    return [(r[0], r[1]) for r in rows]


def _resolve_family(conn, raw: str) -> Optional[str]:
    row = conn.execute(sa.text("""
        SELECT family_name FROM ml_forecast.family_model_registry_v2
        WHERE lower(trim(family_name)) = lower(trim(:fn))
    """), {"fn": raw}).first()
    return row[0] if row else None


# ──────────────────────────────────────────────
# Output helpers
# ──────────────────────────────────────────────

def _print_family_summary(fam: dict, sug_status: Optional[str] = None):
    fn = fam["family_name"]
    if fam["status"] == "skipped":
        print(f"  SKIP   | {fn:<30s} | {fam['reason']}")
        return
    hsum = fam.get("holdout_sum_actual")
    hnz  = fam.get("holdout_nonzero_days")
    hsum_str = f"{hsum:.1f}" if hsum is not None else "?"
    hnz_str  = str(hnz) if hnz  is not None else "?"
    sug_part = f" | sug={sug_status}" if sug_status else ""
    print(
        f"  FAMILY | {fn:<30s} | best={fam['best_model_code']:<24s} "
        f"| holdout_sum={hsum_str} nz_days={hnz_str}{sug_part}"
    )
    for r in fam["results"]:
        star = " ← BEST" if r.get("is_best") else ""
        if r["status"] == "ok":
            print(
                f"    {r['model_code']:<28s} "
                f"wmape={r['wmape']:7.2f}% "
                f"mae={r['mae']:.4f}  "
                f"rmse={r['rmse']:.4f}  "
                f"bias={r['bias']:+.4f}{star}"
            )
        elif r["status"] == "skipped":
            print(f"    {r['model_code']:<28s} SKIP  ({r.get('notes','')})")
        else:
            print(f"    {r['model_code']:<28s} ERROR ({r.get('notes','')})")


# ──────────────────────────────────────────────
# Core runner
# ──────────────────────────────────────────────

def _run_benchmark_list(
    families: list[tuple[str, Optional[str]]],
    scope: str,
    scope_detail: str,
    holdout_days: int,
    model_filter: Optional[list[str]],
    dry_run: bool,
    threshold_pct: float = DEFAULT_SUGGESTION_THRESH,
) -> int:
    db_eng = _get_db_engine()
    try:
        with db_eng.connect() as conn:
            all_models = _get_benchmark_models(conn)

        benchmark_models = model_filter if model_filter else all_models
        if not benchmark_models:
            print("ERROR: nessun modello benchmark_enabled+supports_backtest trovato",
                  file=sys.stderr)
            return 1

        print(
            f"BENCHMARK | scope={scope} | famiglie={len(families)} | "
            f"modelli={len(benchmark_models)} | holdout_days={holdout_days} | "
            f"dry_run={dry_run}"
        )
        print(f"  Modelli candidati: {', '.join(benchmark_models)}")

        if dry_run:
            for fn, _ in families[:5]:
                print(f"  DRY_RUN | {fn}")
            if len(families) > 5:
                print(f"  DRY_RUN | ... +{len(families) - 5} famiglie")
            return 0

        # Crea benchmark run
        with db_eng.begin() as conn:
            run_id = _create_benchmark_run(conn, scope, scope_detail, holdout_days)
            conn.execute(sa.text("""
                UPDATE ml_forecast.family_benchmark_run_v1
                SET families_total = :n
                WHERE run_id = :rid
            """), {"n": len(families), "rid": run_id})
        print(f"  run_id={run_id} creato")

        ok = fail = skipped = total_results = 0

        for fn, assigned_mc in families:
            try:
                fam = _benchmark_family(db_eng, fn, holdout_days, benchmark_models)

                with db_eng.begin() as conn:
                    _write_family_results(conn, fam, run_id)
                    sug_status = _write_suggestion(
                        conn, fam, run_id, assigned_mc, threshold_pct
                    )
                    conn.execute(sa.text("""
                        UPDATE ml_forecast.family_benchmark_run_v1
                        SET families_done = families_done + 1,
                            models_tested = models_tested + :mt
                        WHERE run_id = :rid
                    """), {"mt": len(fam["results"]), "rid": run_id})

                _print_family_summary(fam, sug_status)

                if fam["status"] == "skipped":
                    skipped += 1
                else:
                    ok += 1
                    total_results += len([r for r in fam["results"] if r["status"] == "ok"])

            except Exception as exc:
                fail += 1
                print(f"  ERROR | {fn} | {exc}", file=sys.stderr)

        run_status = "done" if fail == 0 else "done_with_errors"
        with db_eng.begin() as conn:
            _close_benchmark_run(conn, run_id, run_status, ok + skipped, total_results)

        print(
            f"\nBENCHMARK DONE | run_id={run_id} | status={run_status} | "
            f"ok={ok} skip={skipped} fail={fail} | results_written={total_results}"
        )
        return 0 if fail == 0 else 1

    finally:
        db_eng.dispose()


# ──────────────────────────────────────────────
# Azioni CLI
# ──────────────────────────────────────────────

def action_one_family(args) -> int:
    db_eng = _get_db_engine()
    try:
        with db_eng.connect() as conn:
            fn = _resolve_family(conn, args.family)
            if not fn:
                print(f"ERROR: famiglia '{args.family}' non trovata", file=sys.stderr)
                return 1
            row = conn.execute(sa.text("""
                SELECT model_code FROM ml_forecast.family_model_assignment_v1
                WHERE family_name = :fn
            """), {"fn": fn}).first()
            assigned_mc = row[0] if row else None
    finally:
        db_eng.dispose()

    model_filter = None
    if getattr(args, "models", None):
        model_filter = [m.strip() for m in args.models.split(",") if m.strip()]

    return _run_benchmark_list(
        families=[(fn, assigned_mc)],
        scope="one",
        scope_detail=fn,
        holdout_days=getattr(args, "holdout_days", DEFAULT_HOLDOUT_DAYS),
        model_filter=model_filter,
        dry_run=getattr(args, "dry_run", False),
    )


def action_many_families(args) -> int:
    raw_list = [f.strip() for f in args.families.split(",") if f.strip()]
    db_eng = _get_db_engine()
    try:
        families: list[tuple[str, Optional[str]]] = []
        with db_eng.connect() as conn:
            for raw in raw_list:
                fn = _resolve_family(conn, raw)
                if not fn:
                    print(f"WARN: famiglia '{raw}' non trovata, saltata", file=sys.stderr)
                    continue
                row = conn.execute(sa.text("""
                    SELECT model_code FROM ml_forecast.family_model_assignment_v1
                    WHERE family_name = :fn
                """), {"fn": fn}).first()
                families.append((fn, row[0] if row else None))
    finally:
        db_eng.dispose()

    if not families:
        print("ERROR: nessuna famiglia valida trovata", file=sys.stderr)
        return 1

    model_filter = None
    if getattr(args, "models", None):
        model_filter = [m.strip() for m in args.models.split(",") if m.strip()]

    return _run_benchmark_list(
        families=families,
        scope="many",
        scope_detail=args.families[:120],
        holdout_days=getattr(args, "holdout_days", DEFAULT_HOLDOUT_DAYS),
        model_filter=model_filter,
        dry_run=getattr(args, "dry_run", False),
    )


def action_new_families(args) -> int:
    min_days = getattr(args, "min_days_since", DEFAULT_MIN_DAYS_SINCE)
    db_eng = _get_db_engine()
    try:
        with db_eng.connect() as conn:
            families = _get_new_families(conn, min_days)
    finally:
        db_eng.dispose()

    if not families:
        print(f"INFO: nessuna famiglia senza benchmark negli ultimi {min_days} giorni")
        return 0

    return _run_benchmark_list(
        families=families,
        scope="new",
        scope_detail=f"no_benchmark_since_{min_days}d",
        holdout_days=getattr(args, "holdout_days", DEFAULT_HOLDOUT_DAYS),
        model_filter=None,
        dry_run=getattr(args, "dry_run", False),
    )


def action_all_families(args) -> int:
    db_eng = _get_db_engine()
    try:
        with db_eng.connect() as conn:
            families = _get_active_families(conn)
    finally:
        db_eng.dispose()

    is_dry = getattr(args, "dry_run", False)
    if not is_dry and not getattr(args, "yes", False):
        print(f"ATTENZIONE: benchmark su TUTTE le {len(families)} famiglie attive.")
        try:
            confirm = input("Digita 'CONFIRM' per procedere (Ctrl+C per annullare): ").strip()
        except (KeyboardInterrupt, EOFError):
            print("\nOperazione annullata.")
            return 0
        if confirm != "CONFIRM":
            print("Operazione annullata.")
            return 0

    return _run_benchmark_list(
        families=families,
        scope="all",
        scope_detail=f"{len(families)} famiglie attive",
        holdout_days=getattr(args, "holdout_days", DEFAULT_HOLDOUT_DAYS),
        model_filter=None,
        dry_run=is_dry,
    )


# ──────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(
        prog="benchmark_family",
        description=(
            "Benchmark offline dei modelli forecast. "
            "NON modifica assignment. NON fa predict di produzione."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Esempi:
  python jobs/benchmark_family.py benchmark-one-family --family "ciclamino"
  python jobs/benchmark_family.py benchmark-one-family --family "ciclamino" --models ETS_DAMPED,TSB
  python jobs/benchmark_family.py benchmark-many-families --families "ciclamino,grevillea,abutilon"
  python jobs/benchmark_family.py benchmark-new-families --min-days-since 30
  python jobs/benchmark_family.py benchmark-all-families --dry-run
  python jobs/benchmark_family.py benchmark-all-families --holdout-days 14 --yes
        """,
    )
    sub = parser.add_subparsers(dest="action", required=True, metavar="ACTION")

    # ── benchmark-one-family ───────────────────
    p1 = sub.add_parser(
        "benchmark-one-family",
        help="Benchmark su una famiglia specifica",
    )
    p1.add_argument("--family",       required=True, metavar="NOME")
    p1.add_argument("--holdout-days", type=int, default=DEFAULT_HOLDOUT_DAYS,
                    dest="holdout_days", metavar="N",
                    help=f"Giorni di holdout (default {DEFAULT_HOLDOUT_DAYS})")
    p1.add_argument("--models",       default=None, metavar="M1,M2",
                    help="Filtra modelli da benchmarkare (default: tutti)")
    p1.add_argument("--dry-run",      action="store_true", default=False, dest="dry_run",
                    help="Mostra cosa succederebbe senza eseguire nulla")

    # ── benchmark-many-families ────────────────
    p2 = sub.add_parser(
        "benchmark-many-families",
        help="Benchmark su una lista di famiglie (CSV)",
    )
    p2.add_argument("--families",     required=True, metavar="N1,N2,...",
                    help="Nomi famiglia separati da virgola")
    p2.add_argument("--holdout-days", type=int, default=DEFAULT_HOLDOUT_DAYS,
                    dest="holdout_days", metavar="N")
    p2.add_argument("--models",       default=None, metavar="M1,M2")
    p2.add_argument("--dry-run",      action="store_true", default=False, dest="dry_run")

    # ── benchmark-new-families ─────────────────
    p3 = sub.add_parser(
        "benchmark-new-families",
        help="Benchmark famiglie senza run recente",
    )
    p3.add_argument("--holdout-days",   type=int, default=DEFAULT_HOLDOUT_DAYS,
                    dest="holdout_days", metavar="N")
    p3.add_argument("--min-days-since", type=int, default=DEFAULT_MIN_DAYS_SINCE,
                    dest="min_days_since", metavar="N",
                    help=f"Famiglie senza benchmark da almeno N giorni (default {DEFAULT_MIN_DAYS_SINCE})")
    p3.add_argument("--dry-run",        action="store_true", default=False, dest="dry_run")

    # ── benchmark-all-families ─────────────────
    p4 = sub.add_parser(
        "benchmark-all-families",
        help="Benchmark su TUTTE le famiglie attive (richiede conferma)",
    )
    p4.add_argument("--holdout-days", type=int, default=DEFAULT_HOLDOUT_DAYS,
                    dest="holdout_days", metavar="N")
    p4.add_argument("--dry-run",      action="store_true", default=False, dest="dry_run")
    p4.add_argument("--yes",          action="store_true", default=False,
                    help="Salta la conferma interattiva (per uso in script)")

    args = parser.parse_args()

    dispatch = {
        "benchmark-one-family":    action_one_family,
        "benchmark-many-families": action_many_families,
        "benchmark-new-families":  action_new_families,
        "benchmark-all-families":  action_all_families,
    }
    fn = dispatch.get(args.action)
    if not fn:
        print(f"Azione non riconosciuta: {args.action}", file=sys.stderr)
        return 1
    return fn(args)


if __name__ == "__main__":
    raise SystemExit(main())
