from __future__ import annotations

import argparse
import os
import subprocess
import sys
import traceback

import sqlalchemy as sa
from sqlalchemy import text
from sqlalchemy.engine import URL

from jobs.common import load_env, setup_import_path
from jobs.family_resolver import resolve_family_and_slug
from jobs.ml_ops_bridge import (
    check_job_enabled,
    start_pipeline_run,
    finish_pipeline_run,
    start_family_run,
    finish_family_run,
)

load_env()
setup_import_path()


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


def get_family_max_created_at(engine, family_name: str):
    q = text("""
        select max(created_at)
        from public.greenhouse_forecast_results_v2
        where lower(trim(famiglia)) = lower(trim(:family_name))
    """)
    with engine.begin() as conn:
        return conn.execute(q, {"family_name": family_name}).scalar()


def count_family_rows_created_after(engine, family_name: str, ts_marker) -> int:
    if ts_marker is None:
        q = text("""
            select count(*)
            from public.greenhouse_forecast_results_v2
            where lower(trim(famiglia)) = lower(trim(:family_name))
        """)
        with engine.begin() as conn:
            return int(conn.execute(q, {"family_name": family_name}).scalar() or 0)

    q = text("""
        select count(*)
        from public.greenhouse_forecast_results_v2
        where lower(trim(famiglia)) = lower(trim(:family_name))
          and created_at > :ts_marker
    """)
    with engine.begin() as conn:
        return int(conn.execute(q, {"family_name": family_name, "ts_marker": ts_marker}).scalar() or 0)


def push_pipeline_monitor(ok: bool) -> None:
    engine = get_engine()
    try:
        with engine.begin() as conn:
            conn.execute(
                text("insert into public.t_ops_pipeline_monitor(ok) values (:ok)"),
                {"ok": bool(ok)},
            )
    finally:
        engine.dispose()


def run_subprocess(cmd: list[str]) -> int:
    proc = subprocess.run(cmd)
    return int(proc.returncode)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--family", required=True)
    parser.add_argument("--write-db", default="1")
    args = parser.parse_args()

    if not check_job_enabled("predict_family", default=True):
        print("predict_family disabled in ml_ops.job_schedule_config_v1")
        return 0

    family_input = args.family
    write_db = str(args.write_db).strip() not in ("0", "false", "False", "no", "NO")

    engine = get_engine()
    family_name, family_slug = resolve_family_and_slug(engine, family_input)

    pipeline_run_id = None
    family_run_id = None

    try:
        before_marker = get_family_max_created_at(engine, family_name)

        pipeline_run_id = start_pipeline_run(
            job_type="predict_family",
            trigger_mode="manual",
            notes=f"family={family_name} slug={family_slug}",
            env_snapshot={
                "write_db": write_db,
                "pg_host": os.getenv("PG_HOST"),
                "pg_db": os.getenv("PG_DB"),
                "storage_backend": os.getenv("STORAGE_BACKEND"),
                "local_storage_root": os.getenv("LOCAL_STORAGE_ROOT"),
            },
        )

        family_run_id = start_family_run(
            pipeline_run_id=pipeline_run_id,
            job_type="predict_family",
            family_name=family_name,
            demand_class_final=None,
            model_code=None,
        )

        cmd_router = [
            sys.executable,
            "-m",
            "jobs.predict_family_router",
            "--family",
            family_name,
            "--write_db",
            "1" if write_db else "0",
        ]
        rc = run_subprocess(cmd_router)

        router_rows_written = count_family_rows_created_after(engine, family_name, before_marker)

        fallback_used = False
        if rc == 0 and write_db and router_rows_written == 0:
            print(
                f"FALLBACK_TRIGGER family={family_name} slug={family_slug} "
                f"reason=router_zero_rows -> ENGINE_NAIVE_ZERO",
                flush=True,
            )
            cmd_fallback = [
                sys.executable,
                "-c",
                (
                    "from jobs.engines.engine_naive_zero import predict_naive_zero; "
                    f"predict_naive_zero(family_name={family_name!r}, family_slug={family_slug!r}, write_db=True)"
                ),
            ]
            rc = run_subprocess(cmd_fallback)
            fallback_used = (rc == 0)

        rows_written = count_family_rows_created_after(engine, family_name, before_marker)

        if rc == 0:
            finish_family_run(
                family_run_id=family_run_id,
                status="success",
                rows_written=rows_written,
                artifact_path=None,
                error_message=None,
                error_trace=None,
            )
            finish_pipeline_run(
                run_id=pipeline_run_id,
                status="success",
                rows_processed=rows_written,
                error_message=None,
                notes=(
                    f"family={family_name} slug={family_slug} "
                    f"rows_written={rows_written} fallback_used={fallback_used}"
                ),
            )
            push_pipeline_monitor(True)
            print(
                f"PREDICT_FAMILY_LOGGED_OK family={family_name} slug={family_slug} "
                f"rows_written={rows_written} fallback_used={fallback_used}",
                flush=True,
            )
            return 0

        finish_family_run(
            family_run_id=family_run_id,
            status="failed",
            rows_written=rows_written,
            artifact_path=None,
            error_message="predict router/fallback failed",
            error_trace=None,
        )
        finish_pipeline_run(
            run_id=pipeline_run_id,
            status="failed",
            rows_processed=rows_written,
            error_message="predict router/fallback failed",
            notes=f"family={family_name} slug={family_slug}",
        )
        push_pipeline_monitor(False)
        return rc or 1

    except Exception as e:
        err = str(e)
        trace = traceback.format_exc()

        try:
            if family_run_id is not None:
                finish_family_run(
                    family_run_id=family_run_id,
                    status="failed",
                    rows_written=0,
                    artifact_path=None,
                    error_message=err,
                    error_trace=trace,
                )
            if pipeline_run_id is not None:
                finish_pipeline_run(
                    run_id=pipeline_run_id,
                    status="failed",
                    rows_processed=0,
                    error_message=err,
                    notes=f"family={family_name} slug={family_slug}",
                )
            push_pipeline_monitor(False)
        except Exception:
            pass

        print(trace, file=sys.stderr)
        return 1
    finally:
        engine.dispose()


if __name__ == "__main__":
    raise SystemExit(main())
