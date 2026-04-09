import os
import sys
import signal
import subprocess
from datetime import datetime
from pathlib import Path

import sqlalchemy as sa
from sqlalchemy.engine import URL
from jobs.common import load_env, get_log_dir, job_script, setup_import_path, base_arg_parser

load_env()
setup_import_path()

LOG_DIR = str(get_log_dir())

FAMIGLIE_SOURCE_TABLE = os.getenv("FAMIGLIE_SOURCE_TABLE", "public.mv_famiglie_catalog")
FAMIGLIE_COL = os.getenv("FAMIGLIE_COL", "famiglia")

PREDICT_LIMIT = int(os.getenv("PREDICT_LIMIT", "0"))
PREDICT_SCRIPT = job_script("predict_family_router")
PREDICT_ONLY_FAMILY = (os.getenv("PREDICT_ONLY_FAMILY", "") or "").strip().lower()
TRAIN_SCRIPT = job_script("train_family_router")

PER_FAMILY_TIMEOUT = int(os.getenv("PREDICT_FAMILY_TIMEOUT_SEC", "1800"))
TRAIN_TIMEOUT = int(os.getenv("TRAIN_TIMEOUT_SEC", "7200"))

AUTO_TRAIN_MISSING = str(os.getenv("AUTO_TRAIN_MISSING", "1")).lower() in ("1", "true", "yes")

MLOPS_RUN_ID = None
STOP_REQUESTED = False

from jobs.ensure_model_bundle import ensure_bundle, ensure_bundle_any_engine, upload_bundle  # noqa: E402
from jobs.family_resolver import resolve_family_and_slug  # noqa: E402
from jobs.ml_ops_bridge import (  # noqa: E402
    start_pipeline_run as mlops_start_pipeline_run,
    finish_pipeline_run as mlops_finish_pipeline_run,
    start_family_run as mlops_start_family_run,
    finish_family_run as mlops_finish_family_run,
    mark_predict_success as mlops_mark_predict_success,
    mark_predict_failed as mlops_mark_predict_failed,
    check_job_enabled,
)


def _handle_stop(signum, frame):
    global STOP_REQUESTED
    STOP_REQUESTED = True
    raise KeyboardInterrupt(f"signal={signum}")


signal.signal(signal.SIGINT, _handle_stop)
signal.signal(signal.SIGTERM, _handle_stop)


def _stream_child(cmd, logf, timeout_sec: int) -> int:
    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"

    start = datetime.utcnow()
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        env=env,
    )

    try:
        while True:
            if timeout_sec and (datetime.utcnow() - start).total_seconds() > timeout_sec:
                try:
                    proc.kill()
                except Exception:
                    pass
                try:
                    logf.write("\n--- PREDICT TIMEOUT (killed) ---\n")
                    logf.flush()
                except Exception:
                    pass
                return 124

            line = proc.stdout.readline() if proc.stdout is not None else ""
            if line:
                try:
                    logf.write(line)
                    logf.flush()
                except Exception:
                    pass
                try:
                    sys.stdout.write(line)
                    sys.stdout.flush()
                except Exception:
                    pass
                continue

            rc = proc.poll()
            if rc is not None:
                return int(rc)
    finally:
        try:
            if proc.stdout:
                proc.stdout.close()
        except Exception:
            pass


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


def list_families(engine):
    if PREDICT_ONLY_FAMILY:
        fam_list = [f.strip().lower() for f in PREDICT_ONLY_FAMILY.split(",") if f.strip()]
        q = sa.text("""
            select lower(trim(family_name)) as family_name
            from ml_forecast.v_family_execution_routing_v2
            where lower(trim(family_name)) = ANY(:fams)
              and coalesce(is_active, true) = true
            order by 1
        """)
        params = {"fams": fam_list}
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

    fams = []
    for r in rows:
        if not r or not r[0]:
            continue
        fam = str(r[0]).strip().lower()
        if fam:
            fams.append(fam)

    if PREDICT_LIMIT > 0:
        fams = fams[:PREDICT_LIMIT]

    return fams

def run_train(fam: str, logf) -> int:
    cmd = [sys.executable, TRAIN_SCRIPT, "--family", fam]
    start = datetime.utcnow()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=TRAIN_TIMEOUT)
        rc = p.returncode
        out = p.stdout or ""
        err = p.stderr or ""
        status = "OK" if rc == 0 else "FAIL"
    except subprocess.TimeoutExpired as e:
        rc = 124
        out = (e.stdout or "") if hasattr(e, "stdout") else ""
        err = (e.stderr or "") if hasattr(e, "stderr") else ""
        status = "TIMEOUT"

    sec = (datetime.utcnow() - start).total_seconds()
    logf.write(f"\n--- TRAIN {status} | rc={rc} | sec={sec:.1f} | FAMILY={fam} ---\n")
    if out:
        logf.write(out)
    if err:
        logf.write("\n--- TRAIN STDERR ---\n")
        logf.write(err)
    logf.flush()
    return rc


def run_predict(fam: str, logf) -> int:
    cmd = [sys.executable, "-u", PREDICT_SCRIPT, "--family", fam, "--write_db", "1"]
    start = datetime.utcnow()

    try:
        if str(os.getenv("V4_HURDLE_DEBUG", "0")).lower() in ("1", "true", "yes"):
            rc = _stream_child(cmd, logf, timeout_sec=PER_FAMILY_TIMEOUT)
            out = ""
            err = ""
        else:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=PER_FAMILY_TIMEOUT)
            rc = p.returncode
            out = p.stdout or ""
            err = p.stderr or ""
        status = "OK" if rc == 0 else "FAIL"

    except subprocess.TimeoutExpired as e:
        rc = 124
        out = (e.stdout or "") if hasattr(e, "stdout") else ""
        err = (e.stderr or "") if hasattr(e, "stderr") else ""
        status = "TIMEOUT"

    sec = (datetime.utcnow() - start).total_seconds()
    logf.write(f"\n--- PREDICT {status} | rc={rc} | sec={sec:.1f} | FAMILY={fam} ---\n")
    if out:
        logf.write(out)
    if err:
        logf.write("\n--- PREDICT STDERR ---\n")
        logf.write(err)
    logf.flush()
    return rc


def run_one_family(fam: str, logf) -> int:
    global MLOPS_RUN_ID

    if STOP_REQUESTED:
        raise KeyboardInterrupt("stop requested")

    try:
        engine = get_engine()
        fam_name, fam_slug = resolve_family_and_slug(engine, fam)
        engine.dispose()
    except Exception:
        fam_name, fam_slug = fam, fam

    ok_bundle, bundle_msg = ensure_bundle_any_engine(fam_slug)

    if not ok_bundle and AUTO_TRAIN_MISSING:
        logf.write(f"\n\n===== {datetime.utcnow().isoformat()}Z | FAMILY={fam_name} | MISSING_BUNDLE -> TRAIN =====\n")
        logf.write(bundle_msg + "\n")

        rc_train = run_train(fam_name, logf)

        if rc_train != 0:
            logf.write(f"\n===== {datetime.utcnow().isoformat()}Z | FAMILY={fam_name} | TRAIN_FAILED -> SKIP =====\n")
            logf.flush()
            return rc_train

        ok_bundle2, bundle_msg2 = ensure_bundle_any_engine(fam_slug)
        logf.write(bundle_msg2 + "\n")

        if not ok_bundle2:
            logf.write(f"\n===== {datetime.utcnow().isoformat()}Z | FAMILY={fam_name} | STILL_NO_BUNDLE -> SKIP =====\n")
            logf.flush()
            return 2

        logf.write(f"\n===== {datetime.utcnow().isoformat()}Z | FAMILY={fam_name} | TRAIN_OK -> PREDICT =====\n")
        ok_up, up_msg = upload_bundle(fam_slug)
        logf.write(up_msg + "\n")
        logf.flush()

    elif not ok_bundle:
        logf.write(f"\n\n===== {datetime.utcnow().isoformat()}Z | FAMILY={fam_name} | SKIP_NO_BUNDLE =====\n")
        logf.write(bundle_msg + "\n")
        logf.flush()
        return 0

    else:
        logf.write(f"\n\n===== {datetime.utcnow().isoformat()}Z | FAMILY={fam_name} | BUNDLE_OK -> PREDICT =====\n")
        logf.write(bundle_msg + "\n")
        logf.flush()

    mlops_family_run_id = None
    if MLOPS_RUN_ID is not None:
        try:
            mlops_family_run_id = mlops_start_family_run(
                MLOPS_RUN_ID,
                "predict",
                fam_name,
                None,
                None,
            )
        except Exception:
            mlops_family_run_id = None

    pred_rc = None
    try:
        pred_rc = run_predict(fam_name, logf)
    except KeyboardInterrupt:
        if mlops_family_run_id is not None:
            try:
                mlops_finish_family_run(
                    mlops_family_run_id,
                    "failed",
                    None,
                    None,
                    "terminated by signal",
                )
            except Exception:
                pass
        try:
            mlops_mark_predict_failed(fam_name, MLOPS_RUN_ID, "terminated by signal")
        except Exception:
            pass
        raise

    if mlops_family_run_id is not None:
        try:
            mlops_finish_family_run(
                mlops_family_run_id,
                ("success" if pred_rc == 0 else "failed"),
                None,
                None,
                (None if pred_rc == 0 else f"predict rc={pred_rc}"),
            )
        except Exception:
            pass

    try:
        if pred_rc == 0:
            mlops_mark_predict_success(fam_name, MLOPS_RUN_ID, "predict_all ok")
        else:
            mlops_mark_predict_failed(fam_name, MLOPS_RUN_ID, f"predict rc={pred_rc}")
    except Exception:
        pass

    return pred_rc


def main():
    global MLOPS_RUN_ID, PREDICT_LIMIT

    parser = base_arg_parser("Run predict cycle for all active families")
    args = parser.parse_args()
    if args.limit:
        PREDICT_LIMIT = args.limit
    if args.dry_run:
        print(f"DRY_RUN: predict_all | limit={PREDICT_LIMIT} | families would be predicted but no writes")
        return 0
    if args.start_date:
        os.environ.setdefault("PREDICT_START_DATE", args.start_date)
    if args.end_date:
        os.environ.setdefault("PREDICT_END_DATE", args.end_date)

    if not check_job_enabled("predict_daily"):
        print("SKIP: predict_daily disabilitato in ml_ops.job_schedule_config_v1")
        return 0

    os.makedirs(LOG_DIR, exist_ok=True)
    stamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    logfile = os.path.join(LOG_DIR, f"predict_all_{stamp}.log")

    engine = get_engine()
    fams = list_families(engine)
    engine.dispose()

    ok = 0
    bad = 0
    final_status = "fail"
    final_rc = 1
    final_error = None

    with open(logfile, "w", encoding="utf-8") as logf:
        try:
            logf.write(f"START predict_all | fams={len(fams)} | {datetime.utcnow().isoformat()}Z\n")
            logf.write(f"FAM_SOURCE=registry_active | LIMIT={PREDICT_LIMIT}\n")

            try:
                MLOPS_RUN_ID = mlops_start_pipeline_run(
                    "predict_daily",
                    os.getenv("RUN_TRIGGER_SOURCE", "systemd_timer"),
                    f"predict_all fams={len(fams)}",
                    git_sha=os.getenv("GIT_SHA"),
                )
                logf.write(f"ML_OPS RUN_ID={MLOPS_RUN_ID}\n")
            except Exception as e:
                MLOPS_RUN_ID = None
                logf.write(f"ML_OPS start_pipeline_run failed: {e}\n")

            logf.write(f"AUTO_TRAIN_MISSING={AUTO_TRAIN_MISSING}\n")

            for fam in fams:
                if STOP_REQUESTED:
                    raise KeyboardInterrupt("stop requested")
                rc = run_one_family(fam, logf)
                if rc == 0:
                    ok += 1
                else:
                    bad += 1

            logf.write(f"\nEND predict_all | ok={ok} bad={bad} | {datetime.utcnow().isoformat()}Z\n")
            final_status = "ok" if bad == 0 else "fail"
            final_rc = 0 if bad == 0 else 1

        except KeyboardInterrupt:
            final_status = "fail"
            final_rc = 130
            final_error = "terminated by signal"
            logf.write(f"\nINTERRUPTED predict_all | ok={ok} bad={bad} | {datetime.utcnow().isoformat()}Z\n")

        except Exception as e:
            final_status = "fail"
            final_rc = 1
            final_error = str(e)[:4000]
            logf.write(f"\nERROR predict_all | err={final_error} | {datetime.utcnow().isoformat()}Z\n")

    latest = Path(LOG_DIR) / "predict_all_latest.log"
    try:
        latest.unlink(missing_ok=True)
    except TypeError:
        if latest.exists() or latest.is_symlink():
            latest.unlink()
    latest.symlink_to(logfile)

    try:
        if MLOPS_RUN_ID is not None:
            mlops_finish_pipeline_run(
                MLOPS_RUN_ID,
                status=("success" if final_status == "ok" else "failed"),
                rows_processed=(ok + bad),
                error_message=(None if final_status == "ok" else (final_error or f"predict_all rc={final_rc}")),
                notes=f"logfile={logfile}",
            )
    except Exception:
        pass

    print(f"DONE predict_all -> {logfile} | ok={ok} bad={bad} rc={final_rc}")
    return 0 if final_status == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
