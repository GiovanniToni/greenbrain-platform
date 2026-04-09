import os
import json
import time
from datetime import datetime, timedelta, date

import psycopg2
from dotenv import load_dotenv

PROGRESS_FILE = "backfill_features_progress.json"

MAX_RETRIES = 3
RETRY_SLEEP_SEC = 10
STEP_DAYS = 7
STATEMENT_TIMEOUT_MS = 600000  # 10 min

# Consiglio: parti dal 2018 per non esplodere di volume
FORCE_START = None   # metti None se vuoi davvero da min(dense)
FORCE_END = None            # None = fino a max(dense)


def iso_to_date(s: str) -> date:
    return datetime.strptime(s, "%Y-%m-%d").date()


def load_progress():
    if os.path.exists(PROGRESS_FILE):
        with open(PROGRESS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_progress(p):
    with open(PROGRESS_FILE, "w", encoding="utf-8") as f:
        json.dump(p, f, ensure_ascii=False, indent=2)


def db_connect():
    load_dotenv(".env")
    host = os.getenv("PG_HOST")
    port = int(os.getenv("PG_PORT", "5432"))
    db = os.getenv("PG_DB")
    user = os.getenv("PG_USER")
    password = os.getenv("PG_PASSWORD")

    if not all([host, db, user, password]):
        raise RuntimeError("Variabili PG_* mancanti nel .env")

    conn = psycopg2.connect(
        host=host,
        port=port,
        dbname=db,
        user=user,
        password=password,
        sslmode="require",
        connect_timeout=20,
    )
    conn.autocommit = False
    return conn


def get_min_max_dense(conn):
    with conn.cursor() as cur:
        cur.execute("""
            SELECT MIN(data)::date, MAX(data)::date
            FROM public.greenhouse_sales_family_daily_dense
        """)
        return cur.fetchone()


def refresh_features_range(conn, start_d: date, end_d: date):
    with conn.cursor() as cur:
        cur.execute("BEGIN;")
        cur.execute("SET TRANSACTION READ WRITE;")
        cur.execute("SELECT set_config('statement_timeout', %s, true);", (str(STATEMENT_TIMEOUT_MS),))
        cur.execute("SELECT public.refresh_forecast_features_dense_range(%s::date, %s::date);", (start_d, end_d))
        cur.execute("COMMIT;")


def main():
    p = load_progress()
    conn = db_connect()

    mn_dense, mx_dense = get_min_max_dense(conn)
    if mn_dense is None or mx_dense is None:
        raise RuntimeError("greenhouse_sales_family_daily_dense è vuota")

    start_date = iso_to_date(FORCE_START) if FORCE_START else mn_dense
    end_date = iso_to_date(FORCE_END) if FORCE_END else mx_dense

    # riprendi da progress se esiste
    if "next_start" in p and FORCE_START is not None:
        # se stai forzando start, ignoriamo progress vecchi
        pass
    elif "next_start" in p and FORCE_START is None:
        next_start = iso_to_date(p["next_start"])
        if start_date <= next_start <= end_date:
            start_date = next_start

    print("🚀 Backfill FEATURES weekly")
    print("   Range:", start_date, "→", end_date)
    print("   Chunk:", STEP_DAYS, "giorni")
    print("   Progress file:", os.path.abspath(PROGRESS_FILE))

    d = start_date
    while d <= end_date:
        chunk_start = d
        chunk_end = min(end_date, chunk_start + timedelta(days=STEP_DAYS - 1))

        ok = False
        last_exc = None

        for attempt in range(1, MAX_RETRIES + 1):
            try:
                print(f"\n➡️  Range {chunk_start} → {chunk_end}  attempt {attempt}/{MAX_RETRIES}")
                t0 = time.time()
                refresh_features_range(conn, chunk_start, chunk_end)
                dt = time.time() - t0
                print(f"✅ OK  ({dt:.1f}s)")

                next_start = chunk_end + timedelta(days=1)
                p["last_ok_range"] = {"start": chunk_start.isoformat(), "end": chunk_end.isoformat(), "step_days": STEP_DAYS}
                p["next_start"] = next_start.isoformat()
                p["last_error"] = None
                save_progress(p)

                ok = True
                break

            except Exception as e:
                conn.rollback()
                last_exc = e
                msg = f"{type(e).__name__}: {e}"
                print(f"❌ ERROR: {msg}")

                p["last_error"] = {
                    "range": {"start": chunk_start.isoformat(), "end": chunk_end.isoformat(), "step_days": STEP_DAYS},
                    "attempt": attempt,
                    "error": msg,
                }
                save_progress(p)

                if attempt < MAX_RETRIES:
                    print(f"⏳ retry in {RETRY_SLEEP_SEC}s...")
                    time.sleep(RETRY_SLEEP_SEC)

        if not ok:
            print("\n🛑 STOP: chunk fallito dopo retry.")
            print("Last error:", repr(last_exc))
            print("Progress saved in:", os.path.abspath(PROGRESS_FILE))
            conn.close()
            return

        d = chunk_end + timedelta(days=1)

    print("\n🎉 Backfill FEATURES COMPLETATO fino a:", end_date)
    print("Progress saved in:", os.path.abspath(PROGRESS_FILE))
    conn.close()


if __name__ == "__main__":
    main()