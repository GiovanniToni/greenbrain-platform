from pathlib import Path
import os
import sys

REPO_DIR = os.getenv("GH_REPO_DIR", str(Path(__file__).resolve().parents[2]))
if REPO_DIR not in sys.path:
    sys.path.insert(0, REPO_DIR)

import os
import pickle
from dataclasses import dataclass, asdict
from datetime import datetime
from typing import Any

import sys

from jobs.common import get_models_dir, setup_import_path

import numpy as np
import pandas as pd
import sqlalchemy as sa
from sqlalchemy.engine import URL

from jobs.engines.engine_validation import validate_forecast_df
from jobs.engines.fascia_allocator import allocate_family_forecast_using_history
from jobs.engines.forecast_writer import write_forecast_replace_window


MODELS_DIR = get_models_dir()
MIN_DATE = os.getenv("V4_MIN_DATE", "2009-01-01")

if REPO_DIR not in sys.path:
    setup_import_path()

from data_access_v1 import load_family_df_parquet_or_db  # noqa: E402
DEFAULT_HORIZON_DAYS = int(os.getenv("SEASONAL_CROSTON_HORIZON_DAYS", "10"))
DEFAULT_ALPHA = float(os.getenv("SEASONAL_CROSTON_ALPHA", "0.1"))
MIN_MONTHS_FOR_SEASONAL = int(os.getenv("SEASONAL_CROSTON_MIN_MONTHS", "12"))


@dataclass
class SeasonalCrostonBundle:
    engine_name: str
    engine_version: str
    family_name: str
    family_slug: str
    horizon_days: int
    trained_at_utc: str
    demand_rate: float
    alpha: float
    seasonal_factors: dict
    seasonal_method: str
    history_len: int
    metadata: dict[str, Any]


def get_engine():
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


def _bundle_path(family_slug: str) -> str:
    return os.path.join(MODELS_DIR, f"bundle_{family_slug}_seasonal_croston.pkl")


def _load_history(db_engine, family_name: str) -> pd.Series:
    df = load_family_df_parquet_or_db(
        db_engine,
        famiglia=family_name,
        min_date=MIN_DATE,
        famiglia_slug=family_name.strip().lower().replace(" ", "-"),
    )
    if df.empty:
        return pd.Series(dtype=float)
    df["data"] = pd.to_datetime(df["data"], errors="coerce")
    df["qty_venduta"] = pd.to_numeric(df["qty_venduta"], errors="coerce").fillna(0.0).clip(lower=0.0)
    daily = df.groupby("data")["qty_venduta"].sum().sort_index()
    if daily.empty:
        return pd.Series(dtype=float)
    return daily.asfreq("D", fill_value=0.0)


def _croston_sba(y: np.ndarray, alpha: float) -> float:
    """
    Croston SBA (Syntetos-Boylan Approximation) for intermittent demand.
    Returns the per-period demand rate estimate.
    """
    demand_mask = y > 0
    if not demand_mask.any():
        return 0.0

    demand_indices = np.where(demand_mask)[0]
    demand_values = y[demand_mask]

    z_hat = float(demand_values[0])
    if len(demand_indices) == 1:
        p_hat = float(demand_indices[0] + 1)
    else:
        p_hat = float(demand_indices[1] - demand_indices[0])
        for k in range(1, len(demand_indices)):
            z_hat = alpha * demand_values[k] + (1.0 - alpha) * z_hat
            if k < len(demand_indices) - 1:
                interval = float(demand_indices[k + 1] - demand_indices[k])
            else:
                interval = float(len(y) - demand_indices[k])
            p_hat = alpha * interval + (1.0 - alpha) * p_hat

    sba_rate = (1.0 - alpha / 2.0) * z_hat / max(p_hat, 1e-9)
    return max(0.0, sba_rate)


def _compute_monthly_factors(series: pd.Series, min_months: int) -> tuple[dict, str]:
    """
    Compute monthly seasonal indices from a daily time series.

    Groups history by calendar month, computes the mean daily qty per month,
    then normalises so the grand mean equals 1.0 (indices centred at 1.0).

    Returns
    -------
    (factors, method)
    factors : dict {1..12: float}  — seasonal index per month, mean = 1.0
    method  : str                  — "monthly_index" or "uniform"

    Falls back to uniform {1..12: 1.0} when:
    - series is empty
    - fewer than min_months distinct calendar months present
    - total demand is zero
    """
    if series.empty:
        return {m: 1.0 for m in range(1, 13)}, "uniform"

    s = series.copy()
    s.index = pd.to_datetime(s.index)

    months_present = s.resample("MS").sum()
    if len(months_present) < min_months:
        return {m: 1.0 for m in range(1, 13)}, "uniform"

    monthly_avg = s.groupby(s.index.month).mean()

    for m in range(1, 13):
        if m not in monthly_avg.index:
            monthly_avg[m] = 0.0
    monthly_avg = monthly_avg.sort_index()

    grand_mean = monthly_avg.mean()
    if grand_mean <= 0.0:
        return {m: 1.0 for m in range(1, 13)}, "uniform"

    factors = (monthly_avg / grand_mean).to_dict()
    factors = {int(k): max(0.0, float(v)) for k, v in factors.items()}
    return factors, "monthly_index"


def train_seasonal_croston(
    family_name: str,
    family_slug: str,
    horizon_days: int = DEFAULT_HORIZON_DAYS,
    alpha: float = DEFAULT_ALPHA,
) -> str:
    os.makedirs(MODELS_DIR, exist_ok=True)

    db_engine = get_engine()
    try:
        series = _load_history(db_engine, family_name)
    finally:
        db_engine.dispose()

    y = series.values if not series.empty else np.array([], dtype=float)
    demand_rate = _croston_sba(y, alpha) if len(y) > 0 else 0.0
    seasonal_factors, seasonal_method = _compute_monthly_factors(series, MIN_MONTHS_FOR_SEASONAL)

    bundle = SeasonalCrostonBundle(
        engine_name="ENGINE_SEASONAL_CROSTON",
        engine_version="v1",
        family_name=family_name,
        family_slug=family_slug,
        horizon_days=horizon_days,
        trained_at_utc=datetime.utcnow().isoformat() + "Z",
        demand_rate=demand_rate,
        alpha=alpha,
        seasonal_factors=seasonal_factors,
        seasonal_method=seasonal_method,
        history_len=len(y),
        metadata={
            "method": "Croston SBA + Monthly Seasonal Index",
            "min_months_for_seasonal": MIN_MONTHS_FOR_SEASONAL,
            "write_target_table": "public.greenhouse_forecast_results_v2",
        },
    )

    bundle_path = _bundle_path(family_slug)
    with open(bundle_path, "wb") as f:
        pickle.dump(asdict(bundle), f)

    return bundle_path


def load_bundle(family_slug: str) -> dict[str, Any]:
    bundle_path = _bundle_path(family_slug)
    with open(bundle_path, "rb") as f:
        return pickle.load(f)


def predict_seasonal_croston(
    family_name: str,
    family_slug: str,
    write_db: bool = True,
    horizon_days: int | None = None,
) -> pd.DataFrame:
    bundle = load_bundle(family_slug)
    horizon = int(horizon_days or bundle.get("horizon_days") or DEFAULT_HORIZON_DAYS)
    demand_rate = max(0.0, float(bundle.get("demand_rate", 0.0)))

    raw_factors = bundle.get("seasonal_factors", {})
    seasonal_factors: dict[int, float] = {int(k): max(0.0, float(v)) for k, v in raw_factors.items()}
    for m in range(1, 13):
        if m not in seasonal_factors:
            seasonal_factors[m] = 1.0

    start_date = pd.Timestamp.utcnow().normalize()
    dates = pd.date_range(start=start_date, periods=horizon, freq="D")

    qty_values = [
        max(0.0, demand_rate * seasonal_factors.get(d.month, 1.0))
        for d in dates
    ]

    family_df = pd.DataFrame(
        {
            "data": dates.date,
            "famiglia": family_name,
            "qty_forecast": qty_values,
        }
    )

    db_engine = get_engine()
    try:
        df = allocate_family_forecast_using_history(
            engine=db_engine,
            family_forecast_df=family_df,
            family_name=family_name,
            family_slug=family_slug,
        )
        df["engine_name"] = "ENGINE_SEASONAL_CROSTON"

        validate_forecast_df(df)

        if write_db:
            with db_engine.begin() as conn:
                rows_written = write_forecast_replace_window(
                    conn,
                    df=df,
                    family_name=family_name,
                    table_name="public.greenhouse_forecast_results_v2",
                )
            print(f"ENGINE_SEASONAL_CROSTON rows_written={rows_written}")
    finally:
        db_engine.dispose()

    return df
