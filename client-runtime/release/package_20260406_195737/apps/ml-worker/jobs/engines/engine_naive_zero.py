import os
import pickle
from dataclasses import dataclass, asdict
from jobs.common import get_models_dir, setup_import_path
from datetime import datetime
from typing import Any

import pandas as pd
import sqlalchemy as sa
from sqlalchemy.engine import URL

from jobs.engines.engine_validation import validate_forecast_df
from jobs.engines.fascia_allocator import allocate_family_forecast_using_history
from jobs.engines.forecast_writer import write_forecast_replace_window


MODELS_DIR = get_models_dir()
DEFAULT_HORIZON_DAYS = int(os.getenv("NAIVE_ZERO_HORIZON_DAYS", "10"))


@dataclass
class NaiveZeroBundle:
    engine_name: str
    engine_version: str
    family_name: str
    family_slug: str
    horizon_days: int
    trained_at_utc: str
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
    return os.path.join(MODELS_DIR, f"bundle_{family_slug}_naive_zero.pkl")


def train_naive_zero(
    family_name: str,
    family_slug: str,
    horizon_days: int = DEFAULT_HORIZON_DAYS,
) -> str:
    os.makedirs(MODELS_DIR, exist_ok=True)

    bundle = NaiveZeroBundle(
        engine_name="ENGINE_NAIVE_ZERO",
        engine_version="v1",
        family_name=family_name,
        family_slug=family_slug,
        horizon_days=horizon_days,
        trained_at_utc=datetime.utcnow().isoformat() + "Z",
        metadata={
            "strategy": "all future values = 0",
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


def predict_naive_zero(
    family_name: str,
    family_slug: str,
    write_db: bool = True,
    horizon_days: int | None = None,
) -> pd.DataFrame:
    bundle = load_bundle(family_slug)
    horizon = int(horizon_days or bundle.get("horizon_days") or DEFAULT_HORIZON_DAYS)

    start_date = pd.Timestamp.utcnow().normalize()
    dates = pd.date_range(start=start_date, periods=horizon, freq="D")

    family_df = pd.DataFrame(
        {
            "data": dates.date,
            "famiglia": family_name,
            "qty_forecast": 0.0,
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
        df["engine_name"] = "ENGINE_NAIVE_ZERO"

        validate_forecast_df(df)

        if write_db:
            with db_engine.begin() as conn:
                rows_written = write_forecast_replace_window(
                    conn,
                    df=df,
                    family_name=family_name,
                    table_name="public.greenhouse_forecast_results_v2",
                )
            print(f"ENGINE_NAIVE_ZERO rows_written={rows_written}")
    finally:
        db_engine.dispose()

    return df
