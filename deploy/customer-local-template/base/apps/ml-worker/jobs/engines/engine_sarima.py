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

import warnings
import sys

from jobs.common import get_models_dir, setup_import_path

import numpy as np
import pandas as pd
import sqlalchemy as sa
from sqlalchemy.engine import URL
from statsmodels.tsa.statespace.sarimax import SARIMAX

from jobs.engines.engine_validation import validate_forecast_df
from jobs.engines.fascia_allocator import allocate_family_forecast_using_history
from jobs.engines.forecast_writer import write_forecast_replace_window


MODELS_DIR = get_models_dir()
MIN_DATE = os.getenv("V4_MIN_DATE", "2009-01-01")

if REPO_DIR not in sys.path:
    setup_import_path()

from data_access_v1 import load_family_df_parquet_or_db  # noqa: E402
DEFAULT_HORIZON_DAYS = int(os.getenv("SARIMA_HORIZON_DAYS", "10"))

SARIMA_ORDER = (1, 1, 1)
SARIMA_SEASONAL_ORDER = (1, 0, 1, 7)


@dataclass
class SARIMABundle:
    engine_name: str
    engine_version: str
    family_name: str
    family_slug: str
    horizon_days: int
    trained_at_utc: str
    forecasts: list
    order: tuple
    seasonal_order: tuple
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
    return os.path.join(MODELS_DIR, f"bundle_{family_slug}_sarima.pkl")


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


def _fit_forecasts(series: pd.Series, horizon: int) -> list:
    n = len(series)
    fallback = float(series.mean()) if n > 0 else 0.0

    seasonal_period = SARIMA_SEASONAL_ORDER[3]
    min_obs = max(seasonal_period * 2 + sum(SARIMA_ORDER) + sum(SARIMA_SEASONAL_ORDER[:3]), 20)

    if n < min_obs:
        return [max(0.0, fallback)] * horizon

    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            model = SARIMAX(
                series,
                order=SARIMA_ORDER,
                seasonal_order=SARIMA_SEASONAL_ORDER,
                enforce_stationarity=False,
                enforce_invertibility=False,
            )
            fit = model.fit(disp=False, maxiter=200)
        raw = fit.forecast(steps=horizon)
        return [max(0.0, float(v)) for v in raw]
    except Exception:
        return [max(0.0, fallback)] * horizon


def train_sarima(
    family_name: str,
    family_slug: str,
    horizon_days: int = DEFAULT_HORIZON_DAYS,
) -> str:
    os.makedirs(MODELS_DIR, exist_ok=True)

    db_engine = get_engine()
    try:
        series = _load_history(db_engine, family_name)
    finally:
        db_engine.dispose()

    forecasts = _fit_forecasts(series, horizon_days)

    bundle = SARIMABundle(
        engine_name="ENGINE_SARIMA",
        engine_version="v1",
        family_name=family_name,
        family_slug=family_slug,
        horizon_days=horizon_days,
        trained_at_utc=datetime.utcnow().isoformat() + "Z",
        forecasts=forecasts,
        order=SARIMA_ORDER,
        seasonal_order=SARIMA_SEASONAL_ORDER,
        history_len=len(series),
        metadata={
            "order": list(SARIMA_ORDER),
            "seasonal_order": list(SARIMA_SEASONAL_ORDER),
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


def predict_sarima(
    family_name: str,
    family_slug: str,
    write_db: bool = True,
    horizon_days: int | None = None,
) -> pd.DataFrame:
    bundle = load_bundle(family_slug)
    horizon = int(horizon_days or bundle.get("horizon_days") or DEFAULT_HORIZON_DAYS)
    stored = bundle.get("forecasts", [])

    if len(stored) >= horizon:
        qty_values = stored[:horizon]
    else:
        pad = stored[-1] if stored else 0.0
        qty_values = stored + [pad] * (horizon - len(stored))

    start_date = pd.Timestamp.utcnow().normalize()
    dates = pd.date_range(start=start_date, periods=horizon, freq="D")

    family_df = pd.DataFrame(
        {
            "data": dates.date,
            "famiglia": family_name,
            "qty_forecast": [max(0.0, float(v)) for v in qty_values],
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
        df["engine_name"] = "ENGINE_SARIMA"

        validate_forecast_df(df)

        if write_db:
            with db_engine.begin() as conn:
                rows_written = write_forecast_replace_window(
                    conn,
                    df=df,
                    family_name=family_name,
                    table_name="public.greenhouse_forecast_results_v2",
                )
            print(f"ENGINE_SARIMA rows_written={rows_written}")
    finally:
        db_engine.dispose()

    return df
