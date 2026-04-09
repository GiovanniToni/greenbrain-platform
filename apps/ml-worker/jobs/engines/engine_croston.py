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
DEFAULT_HORIZON_DAYS = int(os.getenv("CROSTON_HORIZON_DAYS", "10"))
DEFAULT_ALPHA = float(os.getenv("CROSTON_ALPHA", "0.1"))


@dataclass
class CrostonBundle:
    engine_name: str
    engine_version: str
    family_name: str
    family_slug: str
    horizon_days: int
    trained_at_utc: str
    demand_rate: float
    alpha: float
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
    return os.path.join(MODELS_DIR, f"bundle_{family_slug}_croston.pkl")


def _load_history(db_engine, family_name: str) -> np.ndarray:
    df = load_family_df_parquet_or_db(
        db_engine,
        famiglia=family_name,
        min_date=MIN_DATE,
        famiglia_slug=family_name.strip().lower().replace(" ", "-"),
    )
    if df.empty:
        return np.array([], dtype=float)
    df["data"] = pd.to_datetime(df["data"], errors="coerce")
    df["qty_venduta"] = pd.to_numeric(df["qty_venduta"], errors="coerce").fillna(0.0).clip(lower=0.0)
    daily = df.groupby("data")["qty_venduta"].sum().sort_index()
    if daily.empty:
        return np.array([], dtype=float)
    return daily.asfreq("D", fill_value=0.0).values


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


def train_croston(
    family_name: str,
    family_slug: str,
    horizon_days: int = DEFAULT_HORIZON_DAYS,
    alpha: float = DEFAULT_ALPHA,
) -> str:
    os.makedirs(MODELS_DIR, exist_ok=True)

    db_engine = get_engine()
    try:
        y = _load_history(db_engine, family_name)
    finally:
        db_engine.dispose()

    demand_rate = _croston_sba(y, alpha) if len(y) > 0 else 0.0

    bundle = CrostonBundle(
        engine_name="ENGINE_CROSTON",
        engine_version="v1",
        family_name=family_name,
        family_slug=family_slug,
        horizon_days=horizon_days,
        trained_at_utc=datetime.utcnow().isoformat() + "Z",
        demand_rate=demand_rate,
        alpha=alpha,
        history_len=len(y),
        metadata={
            "method": "Croston SBA",
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


def predict_croston(
    family_name: str,
    family_slug: str,
    write_db: bool = True,
    horizon_days: int | None = None,
) -> pd.DataFrame:
    bundle = load_bundle(family_slug)
    horizon = int(horizon_days or bundle.get("horizon_days") or DEFAULT_HORIZON_DAYS)
    demand_rate = max(0.0, float(bundle.get("demand_rate", 0.0)))

    start_date = pd.Timestamp.utcnow().normalize()
    dates = pd.date_range(start=start_date, periods=horizon, freq="D")

    family_df = pd.DataFrame(
        {
            "data": dates.date,
            "famiglia": family_name,
            "qty_forecast": demand_rate,
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
        df["engine_name"] = "ENGINE_CROSTON"

        validate_forecast_df(df)

        if write_db:
            with db_engine.begin() as conn:
                rows_written = write_forecast_replace_window(
                    conn,
                    df=df,
                    family_name=family_name,
                    table_name="public.greenhouse_forecast_results_v2",
                )
            print(f"ENGINE_CROSTON rows_written={rows_written}")
    finally:
        db_engine.dispose()

    return df
