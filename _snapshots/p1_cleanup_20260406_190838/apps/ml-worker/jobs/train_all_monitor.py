import os
import sys
import signal
import subprocess
from datetime import datetime
from pathlib import Path

import sqlalchemy as sa
from sqlalchemy.engine import URL
from dotenv import load_dotenv

load_dotenv("/opt/greenhouse/.env")

REPO_DIR = os.getenv("GH_REPO_DIR", "/opt/greenhouse/repo")
sys.path.insert(0, REPO_DIR)

from jobs.ml_ops_bridge import (  # noqa: E402
    start_pipeline_run as mlops_start_pipeline_run,
    finish_pipeline_run as mlops_finish_pipeline_run,
    check_job_enabled,
)

MODEL_VERSION = os.getenv("MODEL_VERSION", "v4")
JOBS = int(os.getenv("TRAIN_ALL_JOBS", "4"))
TRAIN_LIMIT = int(os.getenv("TRAIN_LIMIT", "0"))
TRAIN_ONLY_FAMILY = (os.getenv("TRAIN_ONLY_FAMILY", "") or "").strip().lower()

STOP_REQUESTED = False


def _handle_stop(signum, frame):
    global STOP_REQUESTED
    STOP_REQUESTED = True
    raise KeyboardInterrupt(f"signal={signum}")


signal.signal(signal.SIGINT, _handle_stop)
signal.signal(signal.SIGTERM, _handle_stop)


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


def list_families(engine):
    if TRAIN_ONLY_FAMILY:
        q = sa.text("""
            select lower(trim(family_name)) as family_name
            from ml_forecast.v_family_execution_routing_v2
            where lower(trim(family_name)) = :fam
              and coalesce(is_active, true) = true
            order by 1
        """)
        params = {"fam": TRAIN_ONLY_FAMILY}
    else:
        q = sa.text("""
            select lower(trim(family_name)) as family_name
            from ml_forecast.v_family_execution_routing_v2
            where coalesce(is_active, true) = true
            order by 1
        """)
        params = {}

    with engine.connect() as conn:
        rows = conn.execute(q, params).fetchall()

    fams = [str(r[0]).strip().lower() for r in rows if r and r[0]]

    if TRAIN_LIMIT > 0:
        fams = fams[:TRAIN_LIMIT]

    return fams

def main():
    if not check_job_enabled("train_biweekly_all"):
        print("SKIP: train_biweekly_all disabilitato in ml_ops.job_schedule_config_v1")
        return 0

    log_dir = Path("/opt/greenhouse/logs")
    log_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    logfile = log_dir / f"train_all_monitor_{stamp}.log"

    engine = get_engine()
    fams = list_families(engine)
    engine.dispose()

    run_type = os.getenv("RUN_TYPE", "train_all_quarterly")
    trigger_source = os.getenv("RUN_TRIGGER_SOURCE", "systemd_timer")

    mlops_run_id = None
    child = None

    final_status = "fail"
    final_rc = 1
    final_error = None

    try:
        mlops_run_id = mlops_start_pipeline_run(
            job_type="train_biweekly_all",
            trigger_mode=trigger_source,
            notes=(
                f"model_version={MODEL_VERSION}; jobs={JOBS}; "
                f"families={len(fams)}; train_limit={TRAIN_LIMIT}; "
                f"train_only_family={TRAIN_ONLY_FAMILY or ''}"
            ),
            git_sha=os.getenv("GIT_SHA"),
        )

        fam_file = Path("/opt/greenhouse/tmp/families.txt")
        fam_file.parent.mkdir(parents=True, exist_ok=True)
        fam_file.write_text("\n".join(fams) + ("\n" if fams else ""), encoding="utf-8")

        cmd = ["/bin/bash", "-lc", f"/opt/greenhouse/repo/jobs/run_train_all_parallel.sh {JOBS}"]

        env = os.environ.copy()
        env["RUN_TRIGGER_SOURCE"] = trigger_source
        env["MODEL_VERSION"] = MODEL_VERSION
        env.pop("RUN_TYPE", None)
        env.pop("PARENT_RUN_ID", None)

        with logfile.open("w", encoding="utf-8") as logf:
            logf.write(
                f"START train_all_monitor | fams={len(fams)} | jobs={JOBS} | "
                f"mlops_run_id={mlops_run_id} | "
                f"train_limit={TRAIN_LIMIT} | train_only_family={TRAIN_ONLY_FAMILY or ''} | "
                f"{datetime.utcnow().isoformat()}Z\n"
            )
            logf.flush()

            if not fams:
                logf.write("NO_FAMILIES_TO_TRAIN\n")
                logf.write(f"END train_all_monitor | rc=0 | {datetime.utcnow().isoformat()}Z\n")
                logf.flush()
                final_status = "ok"
                final_rc = 0
            else:
                child = subprocess.Popen(
                    cmd,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    env=env,
                    cwd="/opt/greenhouse/repo",
                    bufsize=1,
                )

                try:
                    assert child.stdout is not None
                    for line in child.stdout:
                        logf.write(line)
                        logf.flush()
                    child.wait()
                    final_rc = int(child.returncode)
                    final_status = "ok" if final_rc == 0 else "fail"
                    logf.write(f"\nEND train_all_monitor | rc={final_rc} | {datetime.utcnow().isoformat()}Z\n")
                    logf.flush()
                except KeyboardInterrupt:
                    final_rc = 130
                    final_status = "fail"
                    final_error = "terminated by signal"
                    logf.write(f"\nINTERRUPTED train_all_monitor | rc={final_rc} | {datetime.utcnow().isoformat()}Z\n")
                    logf.flush()

                    if child.poll() is None:
                        try:
                            child.terminate()
                            child.wait(timeout=15)
                        except Exception:
                            try:
                                child.kill()
                            except Exception:
                                pass
                    raise

    except KeyboardInterrupt:
        final_status = "fail"
        final_rc = 130 if final_rc in (None, 1) else final_rc
        if not final_error:
            final_error = "terminated by signal"

    except Exception as e:
        final_status = "fail"
        final_rc = 1
        final_error = str(e)[:4000]

    finally:
        try:
            if mlops_run_id is not None:
                mlops_finish_pipeline_run(
                    mlops_run_id,
                    status=("success" if final_status == "ok" else "failed"),
                    rows_processed=len(fams),
                    error_message=(None if final_status == "ok" else (final_error or f"train_all_monitor rc={final_rc}")),
                    notes=f"logfile={logfile}",
                )
        except Exception:
            pass

    print(
        f"DONE train_all_monitor -> {logfile} | "
        f"rc={final_rc} | mlops_run_id={mlops_run_id}"
    )

    return 0 if final_status == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
