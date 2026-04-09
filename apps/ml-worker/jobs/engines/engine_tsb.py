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
DEFAULT_HORIZON_DAYS = int(os.getenv("TSB_HORIZON_DAYS", "10"))
DEFAULT_ALPHA = float(os.getenv("TSB_ALPHA", "0.1"))
DEFAULT_BETA = float(os.getenv("TSB_BETA", "0.1"))


@dataclass
class TSBBundle:
    engine_name: str
    engine_version: str
    family_name: str
    family_slug: str
    horizon_days: int
    trained_at_utc: str
    demand_probability: float
    demand_size: float
    demand_rate: float
    alpha: float
    beta: float
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
    return os.path.join(MODELS_DIR, f"bundle_{family_slug}_tsb.pkl")


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


def _tsb(y: np.ndarray, alpha: float, beta: float) -> tuple[float, float]:
    """
    Teunter-Syntetos-Babai (TSB) method for intermittent demand.
    Returns (demand_probability, demand_size).
    Alpha updates demand probability; beta updates demand size.
    """
    if len(y) == 0:
        return 0.0, 0.0

    first_demand = next((v for v in y if v > 0), None)
    p = 1.0 if first_demand is not None else 0.0
    z = float(first_demand) if first_demand is not None else 0.0

    for val in y:
        if val > 0:
            p = alpha * 1.0 + (1.0 - alpha) * p
            z = beta * float(val) + (1.0 - beta) * z
        else:
            p = alpha * 0.0 + (1.0 - alpha) * p

    return max(0.0, p), max(0.0, z)


def train_tsb(
    family_name: str,
    family_slug: str,
    horizon_days: int = DEFAULT_HORIZON_DAYS,
    alpha: float = DEFAULT_ALPHA,
    beta: float = DEFAULT_BETA,
) -> str:
    os.makedirs(MODELS_DIR, exist_ok=True)

    db_engine = get_engine()
    try:
        y = _load_history(db_engine, family_name)
    finally:
        db_engine.dispose()

    demand_probability, demand_size = _tsb(y, alpha, beta)
    demand_rate = demand_probability * demand_size

    bundle = TSBBundle(
        engine_name="ENGINE_TSB",
        engine_version="v1",
        family_name=family_name,
        family_slug=family_slug,
        horizon_days=horizon_days,
        trained_at_utc=datetime.utcnow().isoformat() + "Z",
        demand_probability=demand_probability,
        demand_size=demand_size,
        demand_rate=demand_rate,
        alpha=alpha,
        beta=beta,
        history_len=len(y),
        metadata={
            "method": "Teunter-Syntetos-Babai",
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


def predict_tsb(
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
        df["engine_name"] = "ENGINE_TSB"

        validate_forecast_df(df)

        if write_db:
            with db_engine.begin() as conn:
                rows_written = write_forecast_replace_window(
                    conn,
                    df=df,
                    family_name=family_name,
                    table_name="public.greenhouse_forecast_results_v2",
                )
            print(f"ENGINE_TSB rows_written={rows_written}")
    finally:
        db_engine.dispose()

    return df
