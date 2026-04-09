from __future__ import annotations

import argparse
import os
import subprocess
import sys
import traceback
from pathlib import Path

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


def get_models_dir() -> Path:
    p = Path(os.getenv("GH_MODELS_DIR", "/opt/greenbrain/models_v4"))
    p.mkdir(parents=True, exist_ok=True)
    return p


def bundle_path_for_slug(family_slug: str) -> Path:
    return get_models_dir() / f"bundle_{family_slug}_v4.pkl"


def push_pipeline_monitor(ok: bool) -> None:
    engine = get_engine()
    try:
        with engine.begin() as conn:
            conn.execute(
                text("insert into public.t_ops_pipeline_monitor (ok) values (:ok)"),
                {"ok": bool(ok)},
            )
    finally:
        engine.dispose()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--family", required=True)
    args = parser.parse_args()

    if not check_job_enabled("train_family", default=True):
        print("train_family disabled in ml_ops.job_schedule_config_v1")
        return 0

    family_input = args.family

    engine = get_engine()
    pipeline_run_id = None
    family_run_id = None

    try:
        family_name, family_slug = resolve_family_and_slug(engine, family_input)
        bundle_path = bundle_path_for_slug(family_slug)
        existed_before = bundle_path.exists()

        pipeline_run_id = start_pipeline_run(
            job_type="train_family",
            trigger_mode="manual",
            notes=f"family={family_name} slug={family_slug}",
            env_snapshot={
                "pg_host": os.getenv("PG_HOST"),
                "pg_db": os.getenv("PG_DB"),
                "storage_backend": os.getenv("STORAGE_BACKEND"),
                "local_storage_root": os.getenv("LOCAL_STORAGE_ROOT"),
                "gh_models_dir": os.getenv("GH_MODELS_DIR"),
            },
        )

        family_run_id = start_family_run(
            pipeline_run_id=pipeline_run_id,
            job_type="train_family",
            family_name=family_name,
            demand_class_final=None,
            model_code="V4_TWEEDIE_BUNDLE",
        )

        cmd = [
            sys.executable,
            "train_v4_single_family_tweedie.py",
            "--family",
            family_name,
        ]

        proc = subprocess.run(cmd, capture_output=True, text=True)

        exists_after = bundle_path.exists()
        artifact_path = str(bundle_path) if exists_after else None

        rows_written = 1 if exists_after and (not existed_before or bundle_path.stat().st_size > 0) else 0

        if proc.returncode == 0:
            finish_family_run(
                family_run_id=family_run_id,
                status="success",
                rows_written=rows_written,
                artifact_path=artifact_path,
                error_message=None,
                error_trace=None,
            )
            finish_pipeline_run(
                run_id=pipeline_run_id,
                status="success",
                rows_processed=rows_written,
                error_message=None,
                notes=f"family={family_name} slug={family_slug}",
            )
            push_pipeline_monitor(True)

            if proc.stdout:
                print(proc.stdout, end="")
            if proc.stderr:
                print(proc.stderr, file=sys.stderr, end="")

            print(
                f"TRAIN_FAMILY_LOGGED_OK family={family_name} slug={family_slug} artifact_path={artifact_path}"
            )
            return 0

        err = (proc.stderr or proc.stdout or "").strip()

        finish_family_run(
            family_run_id=family_run_id,
            status="failed",
            rows_written=rows_written,
            artifact_path=artifact_path,
            error_message=err[:4000] if err else "train failed",
            error_trace=None,
        )
        finish_pipeline_run(
            run_id=pipeline_run_id,
            status="failed",
            rows_processed=rows_written,
            error_message=err[:4000] if err else "train failed",
            notes=f"family={family_name} slug={family_slug}",
        )
        push_pipeline_monitor(False)

        if proc.stdout:
            print(proc.stdout, end="")
        if proc.stderr:
            print(proc.stderr, file=sys.stderr, end="")

        return proc.returncode or 1

    except Exception as e:
        err = str(e)
        tr = traceback.format_exc()

        if family_run_id:
            try:
                finish_family_run(
                    family_run_id=family_run_id,
                    status="failed",
                    rows_written=0,
                    artifact_path=None,
                    error_message=err[:4000],
                    error_trace=tr[:12000],
                )
            except Exception:
                pass

        if pipeline_run_id:
            try:
                finish_pipeline_run(
                    run_id=pipeline_run_id,
                    status="failed",
                    rows_processed=0,
                    error_message=err[:4000],
                    notes="exception in train_family_logged",
                )
            except Exception:
                pass

        try:
            push_pipeline_monitor(False)
        except Exception:
            pass

        print(tr, file=sys.stderr)
        return 1

    finally:
        engine.dispose()


if __name__ == "__main__":
    raise SystemExit(main())
