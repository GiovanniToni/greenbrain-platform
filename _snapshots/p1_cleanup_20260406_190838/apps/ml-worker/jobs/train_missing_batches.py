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

BATCH_SIZE = int(os.getenv("TRAIN_BATCH_SIZE", "10"))
TRAIN_LIMIT = int(os.getenv("TRAIN_LIMIT", "0"))
TRAIN_TIMEOUT = int(os.getenv("TRAIN_TIMEOUT_SEC", "7200"))

TRAIN_SCRIPT = os.path.join(REPO_DIR, "jobs/train_family_router.py")
PARQUET_ENABLE = os.getenv("PARQUET_ENABLE", "1")

MLOPS_RUN_ID = None
STOP_REQUESTED = False

from jobs.ensure_model_bundle import ensure_bundle, ensure_bundle_any_engine, upload_bundle  # noqa: E402
from jobs.family_resolver import resolve_family_and_slug  # noqa: E402
from jobs.ml_ops_bridge import (  # noqa: E402
    start_pipeline_run as mlops_start_pipeline_run,
    finish_pipeline_run as mlops_finish_pipeline_run,
    start_family_run as mlops_start_family_run,
    finish_family_run as mlops_finish_family_run,
    mark_train_success as mlops_mark_train_success,
    mark_train_failed as mlops_mark_train_failed,
    check_job_enabled,
)


def _handle_stop(signum, frame):
    global STOP_REQUESTED
    STOP_REQUESTED = True
    raise KeyboardInterrupt(f"signal={signum}")


signal.signal(signal.SIGINT, _handle_stop)
signal.signal(signal.SIGTERM, _handle_stop)


def get_engine():
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


def list_candidate_families(engine):
    q = sa.text("""
        select lower(trim(family_name)) as family_name
        from ml_forecast.v_family_execution_routing_v2
        where coalesce(is_active, true) = true
          and (
                coalesce(needs_initial_train, false) = true
             or coalesce(needs_retrain, false) = true
          )
        order by 1
    """)

    with engine.connect() as conn:
        rows = conn.execute(q).fetchall()

    fams = []
    for (v,) in rows:
        if v is None:
            continue
        fam = str(v).strip().lower()
        if fam:
            fams.append(fam)
    return fams


def canonicalize_family(engine, fam: str):
    try:
        fam_name, fam_slug = resolve_family_and_slug(engine, fam)
        return fam_name, fam_slug
    except Exception:
        return fam, fam.replace(" ", "-")


def run_train(fam_name: str, logf):
    env = os.environ.copy()
    env["PARQUET_ENABLE"] = str(PARQUET_ENABLE)

    cmd = [sys.executable, TRAIN_SCRIPT, "--family", fam_name]
    t0 = datetime.utcnow()

    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=TRAIN_TIMEOUT, env=env)
        rc = p.returncode
        out = p.stdout or ""
        err = p.stderr or ""
    except subprocess.TimeoutExpired:
        rc = 124
        out = ""
        err = f"TIMEOUT after {TRAIN_TIMEOUT}s"

    dt = (datetime.utcnow() - t0).total_seconds()
    logf.write(f"\n--- TRAIN rc={rc} sec={dt:.1f} fam={fam_name} ---\n")
    if out:
        logf.write(out)
    if err:
        logf.write("\n--- STDERR ---\n")
        logf.write(err + "\n")
    logf.flush()
    return rc


def main():
    global MLOPS_RUN_ID, STOP_REQUESTED

    if not check_job_enabled("train_missing"):
        print("SKIP: train_missing disabilitato in ml_ops.job_schedule_config_v1")
        return 0

    LOG_DIR = os.getenv("GH_LOG_DIR", "/opt/greenhouse/logs")
    os.makedirs(LOG_DIR, exist_ok=True)
    stamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    logfile = os.path.join(LOG_DIR, f"train_missing_{stamp}.log")

    engine = get_engine()
    fams_raw = list_candidate_families(engine)

    fams = []
    seen = set()
    for fam in fams_raw:
        fam_name, fam_slug = canonicalize_family(engine, fam)
        key = (fam_name, fam_slug)
        if key in seen:
            continue
        seen.add(key)
        fams.append((fam_name, fam_slug))

    if TRAIN_LIMIT > 0:
        fams = fams[:TRAIN_LIMIT]

    to_do = fams[:BATCH_SIZE]
    engine.dispose()

    final_status = "ok"
    final_rc = 0
    final_error = None
    okc = 0
    bad = 0

    with open(logfile, "w", encoding="utf-8") as logf:
        try:
            try:
                MLOPS_RUN_ID = mlops_start_pipeline_run(
                    "train_missing",
                    os.getenv("RUN_TRIGGER_SOURCE", "systemd_timer"),
                    f"train_missing candidates={len(fams)} batch={len(to_do)}",
                    git_sha=os.getenv("GIT_SHA"),
                )
                logf.write(f"ML_OPS RUN_ID={MLOPS_RUN_ID}\n")
            except Exception as e:
                MLOPS_RUN_ID = None
                logf.write(f"ML_OPS start_pipeline_run failed: {e}\n")

            logf.write(
                f"START train_missing | candidates={len(fams)} "
                f"batch={len(to_do)} | {datetime.utcnow().isoformat()}Z\n"
            )
            logf.write(
                f"PARQUET_ENABLE={PARQUET_ENABLE} | TRAIN_TIMEOUT={TRAIN_TIMEOUT}\n"
            )
            logf.flush()

            for fam_name, fam_slug in to_do:
                if STOP_REQUESTED:
                    raise KeyboardInterrupt("stop requested before next family")

                logf.write(
                    f"\n===== {datetime.utcnow().isoformat()}Z | FAMILY={fam_name} | "
                    f"SLUG={fam_slug} | STATE_DRIVEN_TRAIN =====\n"
                )
                logf.flush()

                mlops_family_run_id = None
                if MLOPS_RUN_ID is not None:
                    try:
                        mlops_family_run_id = mlops_start_family_run(
                            MLOPS_RUN_ID,
                            "train_missing",
                            fam_name,
                            None,
                            None,
                        )
                    except Exception as e:
                        logf.write(f"\nMLOPS start_family_run failed | family={fam_name} | err={e}\n")
                        logf.flush()

                rc = run_train(fam_name, logf)

                if STOP_REQUESTED and rc == 0:
                    rc = 130

                if rc != 0:
                    bad += 1

                    if mlops_family_run_id is not None:
                        try:
                            mlops_finish_family_run(
                                mlops_family_run_id,
                                "failed",
                                None,
                                None,
                                ("terminated by signal" if rc == 130 else f"train rc={rc}"),
                            )
                        except Exception as e:
                            logf.write(f"\nMLOPS finish_family_run failed | family={fam_name} | err={e}\n")
                            logf.flush()

                    try:
                        mlops_mark_train_failed(
                            fam_name,
                            MLOPS_RUN_ID,
                            ("terminated by signal" if rc == 130 else f"train rc={rc}")
                        )
                    except Exception as e:
                        logf.write(f"\nMLOPS mark_train_failed failed | family={fam_name} | err={e}\n")
                        logf.flush()

                    if rc == 130:
                        raise KeyboardInterrupt("train_missing interrupted during family train")

                    continue

                ok2, msg2 = ensure_bundle_any_engine(fam_slug)
                logf.write(msg2 + "\n")

                ok_up, up_msg = upload_bundle(fam_slug)
                logf.write(up_msg + "\n")
                logf.flush()

                bundle_path = f"/opt/greenhouse/repo/models_v4/bundle_{fam_slug}_v4.pkl"
                bp = Path(bundle_path)

                if mlops_family_run_id is not None:
                    try:
                        mlops_finish_family_run(
                            mlops_family_run_id,
                            ("success" if ok_up else "failed"),
                            1,
                            (bundle_path if bp.exists() else None),
                            (None if ok_up else "upload_bundle failed"),
                        )
                    except Exception as e:
                        logf.write(f"\nMLOPS finish_family_run failed | family={fam_name} | err={e}\n")
                        logf.flush()

                try:
                    if ok_up:
                        mlops_mark_train_success(
                            fam_name,
                            MLOPS_RUN_ID,
                            None,
                            None,
                            "train_missing ok",
                        )
                    else:
                        mlops_mark_train_failed(
                            fam_name,
                            MLOPS_RUN_ID,
                            "upload_bundle failed",
                        )
                except Exception as e:
                    logf.write(f"\nMLOPS mark_train_* failed | family={fam_name} | err={e}\n")
                    logf.flush()

                if ok_up:
                    okc += 1
                else:
                    bad += 1

            logf.write(f"\nEND train_missing | ok={okc} bad={bad} | {datetime.utcnow().isoformat()}Z\n")
            logf.flush()

        except KeyboardInterrupt as e:
            final_status = "fail"
            final_rc = 130
            final_error = f"terminated by signal ({e})"
            logf.write(f"\nINTERRUPTED train_missing | err={final_error} | {datetime.utcnow().isoformat()}Z\n")
            logf.flush()

        except Exception as e:
            final_status = "fail"
            final_rc = 1
            final_error = str(e)
            logf.write(f"\nFATAL train_missing | err={e} | {datetime.utcnow().isoformat()}Z\n")
            logf.flush()

    try:
        if MLOPS_RUN_ID is not None:
            mlops_finish_pipeline_run(
                MLOPS_RUN_ID,
                status=("success" if final_status == "ok" else "failed"),
                rows_processed=int(okc + bad),
                error_message=(None if final_status == "ok" else final_error or f"train_missing rc={final_rc}"),
                notes=f"logfile={logfile}",
            )
    except Exception:
        pass

    print(f"DONE train_missing -> {logfile} | trained={len(to_do)} | ok={okc} | bad={bad} | rc={final_rc}")
    return 0 if final_status == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
