import os
import sys
import subprocess
from datetime import datetime
import sqlalchemy as sa
from sqlalchemy.engine import URL
from jobs.common import load_env, job_script, setup_import_path, base_arg_parser

load_env()
setup_import_path()

FAMIGLIE_SOURCE_TABLE = os.getenv("FAMIGLIE_SOURCE_TABLE", "public.mv_famiglie_catalog")
FAMIGLIE_COL = os.getenv("FAMIGLIE_COL", "famiglia")

BATCH_SIZE = int(os.getenv("TRAIN_BATCH_SIZE", "10"))
TRAIN_LIMIT = int(os.getenv("TRAIN_LIMIT", "0"))  # 0 = no limit
TRAIN_TIMEOUT = int(os.getenv("TRAIN_TIMEOUT_SEC", "7200"))

TRAIN_SCRIPT = job_script("train_family_router")

from jobs.ensure_model_bundle import upload_bundle  # noqa: E402


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
    q = sa.text(
        f"select {FAMIGLIE_COL} from {FAMIGLIE_SOURCE_TABLE} "
        f"where {FAMIGLIE_COL} is not null order by 1;"
    )
    with engine.connect() as conn:
        rows = conn.execute(q).fetchall()
    fams = []
    for (v,) in rows:
        s = str(v).strip()
        if s:
            fams.append(s)
    return fams


def run_train(fam: str):
    cmd = [sys.executable, TRAIN_SCRIPT, "--family", fam]
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=TRAIN_TIMEOUT)
    return p.returncode, p.stdout, p.stderr


def main():
    engine = get_engine()
    fams = list_families(engine)
    engine.dispose()

    if TRAIN_LIMIT > 0:
        fams = fams[:TRAIN_LIMIT]

    total = len(fams)
    print(f"TRAIN_ALL start | total_fams={total} | batch={BATCH_SIZE} | {datetime.utcnow().isoformat()}Z")

    trained = 0
    for i, fam in enumerate(fams, 1):
        print(f"\n===== {datetime.utcnow().isoformat()}Z | {i}/{total} | FAMILY={fam} | TRAIN =====")
        rc, out, err = run_train(fam)
        if out:
            print(out, end="" if out.endswith("\n") else "\n")
        if err:
            print(err, end="" if err.endswith("\n") else "\n")

        if rc == 0:
            ok_up, up_msg = upload_bundle(fam)
            print(up_msg)
            trained += 1
        else:
            print(f"[FAIL] train rc={rc} family={fam}")

        # stop after one batch
        if trained > 0 and (trained % BATCH_SIZE) == 0:
            print(f"\nBATCH_DONE trained={trained} | {datetime.utcnow().isoformat()}Z")
            break

    print(f"\nDONE train_all | trained={trained} | {datetime.utcnow().isoformat()}Z")


if __name__ == "__main__":
    main()
