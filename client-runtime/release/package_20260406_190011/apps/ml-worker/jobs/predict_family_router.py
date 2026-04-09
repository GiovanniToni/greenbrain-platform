import os
import sys
import argparse
import subprocess

import sqlalchemy as sa
from sqlalchemy.engine import URL
from jobs.common import load_env, worker_script, setup_import_path, base_arg_parser

load_env()
setup_import_path()

PREDICT_V4_SCRIPT = worker_script("predict_v4_single_family_tweedie")

from jobs.engines.engine_naive_zero import predict_naive_zero  # noqa: E402
from jobs.engines.engine_ets import predict_ets  # noqa: E402
from jobs.engines.engine_croston import predict_croston  # noqa: E402
from jobs.engines.engine_tsb import predict_tsb  # noqa: E402
from jobs.engines.engine_sarima import predict_sarima  # noqa: E402
from jobs.engines.engine_seasonal_croston import predict_seasonal_croston  # noqa: E402


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


def fetch_family_route(engine, family_name: str):
    q = sa.text("""
        select
            family_name,
            demand_class_final,
            model_code,
            registry_execution_engine,
            target_execution_engine,
            current_execution_engine,
            effective_execution_engine,
            routing_source,
            is_active
        from ml_forecast.v_family_execution_routing_v2
        where lower(trim(family_name)) = lower(trim(:family_name))
        limit 1
    """)
    with engine.connect() as conn:
        row = conn.execute(q, {"family_name": family_name}).mappings().first()
    return row


def run_cmd(cmd):
    p = subprocess.run(cmd)
    return int(p.returncode)


def slugify_family_name(family_name: str) -> str:
    return family_name.strip().lower().replace(" ", "-")


def main():
    parser = base_arg_parser("Route predict for a single family to the best available engine")
    parser.add_argument("--family", required=True)
    parser.add_argument("--write_db", default="1")
    args = parser.parse_args()

    fam = args.family.strip()
    if not fam:
        print("family vuota", file=sys.stderr)
        return 2

    write_db = str(args.write_db).strip() not in ("0", "false", "False")

    engine = get_engine()
    try:
        route = fetch_family_route(engine, fam)
    finally:
        engine.dispose()

    if not route:
        print(f"Famiglia non trovata nel routing: {fam}", file=sys.stderr)
        return 3

    if route["is_active"] is False:
        print(f"Famiglia non attiva nel routing: {route['family_name']}", file=sys.stderr)
        return 4

    effective_engine = route["effective_execution_engine"]
    model_code = route["model_code"]
    family_name = route["family_name"]
    family_slug = slugify_family_name(family_name)

    print(
        "PREDICT_ROUTER | "
        f"family={family_name} | "
        f"class={route['demand_class_final']} | "
        f"model_code={model_code} | "
        f"effective_execution_engine={effective_engine} | "
        f"routing_source={route['routing_source']}"
    )

    if effective_engine == "V4_TWEEDIE_BUNDLE":
        cmd = [
            sys.executable,
            PREDICT_V4_SCRIPT,
            "--family", family_name,
            "--write_db", "1" if write_db else "0",
        ]
        return run_cmd(cmd)

    if effective_engine == "ENGINE_NAIVE_ZERO":
        df = predict_naive_zero(
            family_name=family_name,
            family_slug=family_slug,
            write_db=write_db,
        )
        print(f"NAIVE_ZERO predict righe generate: {len(df)}")
        return 0

    if effective_engine == "ENGINE_ETS":
        df = predict_ets(
            family_name=family_name,
            family_slug=family_slug,
            write_db=write_db,
        )
        print(f"ENGINE_ETS predict righe generate: {len(df)}")
        return 0

    if effective_engine == "ENGINE_CROSTON":
        df = predict_croston(
            family_name=family_name,
            family_slug=family_slug,
            write_db=write_db,
        )
        print(f"ENGINE_CROSTON predict righe generate: {len(df)}")
        return 0

    if effective_engine == "ENGINE_TSB":
        df = predict_tsb(
            family_name=family_name,
            family_slug=family_slug,
            write_db=write_db,
        )
        print(f"ENGINE_TSB predict righe generate: {len(df)}")
        return 0

    if effective_engine == "ENGINE_SARIMA":
        df = predict_sarima(
            family_name=family_name,
            family_slug=family_slug,
            write_db=write_db,
        )
        print(f"ENGINE_SARIMA predict righe generate: {len(df)}")
        return 0

    if effective_engine == "ENGINE_SEASONAL_CROSTON":
        df = predict_seasonal_croston(
            family_name=family_name,
            family_slug=family_slug,
            write_db=write_db,
        )
        print(f"ENGINE_SEASONAL_CROSTON predict righe generate: {len(df)}")
        return 0

    print(
        f"Execution engine non ancora implementato nel router: {effective_engine}",
        file=sys.stderr,
    )
    return 5


if __name__ == "__main__":
    raise SystemExit(main())
