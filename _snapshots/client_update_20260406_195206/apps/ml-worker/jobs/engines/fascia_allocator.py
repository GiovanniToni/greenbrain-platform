from pathlib import Path
import os
import sys

REPO_DIR = os.getenv("GH_REPO_DIR", str(Path(__file__).resolve().parents[2]))
if REPO_DIR not in sys.path:
    sys.path.insert(0, REPO_DIR)

import os
import sys

from jobs.common import get_models_dir, setup_import_path
from typing import Optional

import numpy as np
import pandas as pd


if REPO_DIR not in sys.path:
    setup_import_path()

from data_access_v1 import load_hist_for_predict_parquet_or_db  # noqa: E402

_REQUIRED_FORECAST_COLS = {"data", "famiglia", "qty_forecast"}

_FALLBACK_SHARE_DF = pd.DataFrame(
    {"fascia_prezzo_iva_inc": [0], "share": [1.0]}
)


def _validate_forecast_input(df: pd.DataFrame) -> None:
    missing = _REQUIRED_FORECAST_COLS - set(df.columns)
    if missing:
        raise ValueError(
            f"family_forecast_df missing required columns: {sorted(missing)}. "
            f"Present: {sorted(df.columns.tolist())}"
        )


def build_fascia_share_map(
    engine,
    family_name: str,
    family_slug: Optional[str] = None,
) -> pd.DataFrame:
    """
    Load historical fascia-level demand via parquet-first loader and compute
    each fascia's share of total family demand.

    Parameters
    ----------
    engine : SQLAlchemy engine
        Used as DB fallback inside load_hist_for_predict_parquet_or_db.
    family_name : str
        Human-readable family name (e.g. "phalaenopsis").
    family_slug : str or None
        Optional canonical slug (e.g. "phalaenopsis").  Derived from
        family_name if not provided.

    Returns
    -------
    pd.DataFrame with columns:
        - fascia_prezzo_iva_inc  (int / original dtype)
        - share                  (float, sums to 1.0)
    Sorted ascending by fascia_prezzo_iva_inc.
    Falls back to a single row (fascia=0, share=1.0) when history is empty
    or all quantities are zero.
    """
    slug = family_slug or family_name.strip().lower().replace(" ", "-")

    hist = load_hist_for_predict_parquet_or_db(
        engine,
        famiglia=family_name,
        famiglia_slug=slug,
    )

    if hist.empty or "qty_venduta" not in hist.columns or "fascia_prezzo_iva_inc" not in hist.columns:
        return _FALLBACK_SHARE_DF.copy()

    hist = hist.copy()
    hist["qty_venduta"] = (
        pd.to_numeric(hist["qty_venduta"], errors="coerce")
        .fillna(0.0)
        .clip(lower=0.0)
    )

    fascia_totals = (
        hist.groupby("fascia_prezzo_iva_inc", sort=True)["qty_venduta"]
        .sum()
        .reset_index()
    )
    fascia_totals.columns = ["fascia_prezzo_iva_inc", "qty_total"]

    total_family_qty = fascia_totals["qty_total"].sum()
    if total_family_qty <= 0.0:
        return _FALLBACK_SHARE_DF.copy()

    fascia_totals["share"] = fascia_totals["qty_total"] / total_family_qty

    return (
        fascia_totals[["fascia_prezzo_iva_inc", "share"]]
        .sort_values("fascia_prezzo_iva_inc")
        .reset_index(drop=True)
    )


def allocate_family_forecast_to_fasce(
    family_forecast_df: pd.DataFrame,
    fascia_share_df: pd.DataFrame,
) -> pd.DataFrame:
    """
    Expand a family-level daily forecast into per-fascia rows using
    pre-computed fascia shares.

    Parameters
    ----------
    family_forecast_df : pd.DataFrame
        Must contain: data, famiglia, qty_forecast.
        Each row represents one forecast date at family level.
    fascia_share_df : pd.DataFrame
        Output of build_fascia_share_map().
        Must contain: fascia_prezzo_iva_inc, share.

    Returns
    -------
    pd.DataFrame with columns:
        data, famiglia, fascia_prezzo_iva_inc, qty_forecast, created_at
    One row per (date × fascia).
    Per-date totals are preserved exactly (normalised to match original
    family qty_forecast after floating-point allocation).
    All qty_forecast values are non-negative.
    """
    _validate_forecast_input(family_forecast_df)

    family_forecast_df = family_forecast_df.copy()
    family_forecast_df["qty_forecast"] = (
        pd.to_numeric(family_forecast_df["qty_forecast"], errors="coerce")
        .fillna(0.0)
        .clip(lower=0.0)
    )

    fascia_share_df = fascia_share_df.copy()
    fascia_share_df["share"] = (
        pd.to_numeric(fascia_share_df["share"], errors="coerce")
        .fillna(0.0)
        .clip(lower=0.0)
    )

    # Re-normalise shares defensively so they sum to exactly 1.0
    total_share = fascia_share_df["share"].sum()
    if total_share <= 0.0:
        fascia_share_df = _FALLBACK_SHARE_DF.copy()
        total_share = 1.0
    fascia_share_df["share"] = fascia_share_df["share"] / total_share

    created_at = pd.Timestamp.utcnow()

    rows = []
    for _, fcast_row in family_forecast_df.iterrows():
        date = fcast_row["data"]
        famiglia = fcast_row["famiglia"]
        family_qty = float(fcast_row["qty_forecast"])

        allocated = fascia_share_df["share"].values * family_qty
        allocated = np.clip(allocated, 0.0, None)

        # Normalise: ensure sum == family_qty (handle floating-point drift)
        alloc_sum = allocated.sum()
        if alloc_sum > 0.0:
            allocated = allocated * (family_qty / alloc_sum)

        for i, frow in fascia_share_df.iterrows():
            rows.append(
                {
                    "data": date,
                    "famiglia": famiglia,
                    "fascia_prezzo_iva_inc": frow["fascia_prezzo_iva_inc"],
                    "qty_forecast": max(0.0, float(allocated[i])),
                    "created_at": created_at,
                }
            )

    if not rows:
        return pd.DataFrame(
            columns=["data", "famiglia", "fascia_prezzo_iva_inc", "qty_forecast", "created_at"]
        )

    result = pd.DataFrame(rows)
    result = result.sort_values(["data", "fascia_prezzo_iva_inc"]).reset_index(drop=True)
    return result


def allocate_family_forecast_using_history(
    engine,
    family_forecast_df: pd.DataFrame,
    family_name: str,
    family_slug: Optional[str] = None,
) -> pd.DataFrame:
    """
    Convenience wrapper: build fascia shares from history, then allocate.

    Parameters
    ----------
    engine : SQLAlchemy engine
    family_forecast_df : pd.DataFrame
        Family-level forecast with columns: data, famiglia, qty_forecast.
    family_name : str
    family_slug : str or None

    Returns
    -------
    pd.DataFrame with columns:
        data, famiglia, fascia_prezzo_iva_inc, qty_forecast, created_at
    """
    _validate_forecast_input(family_forecast_df)

    fascia_share_df = build_fascia_share_map(
        engine,
        family_name=family_name,
        family_slug=family_slug,
    )

    return allocate_family_forecast_to_fasce(family_forecast_df, fascia_share_df)
