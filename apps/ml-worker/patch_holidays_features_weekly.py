import os
import json
import time
from datetime import datetime, timedelta, date

import psycopg2
from dotenv import load_dotenv

PROGRESS_FILE = "patch_holidays_progress.json"

MAX_RETRIES = 3
RETRY_SLEEP_SEC = 10
STEP_DAYS = 7

STATEMENT_TIMEOUT_MS = 600000  # 10 min


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
    # IMPORTANT: passiamo esplicitamente il path per evitare l'AssertionError di find_dotenv()
    load_dotenv(".env")

    host = os.getenv("PG_HOST")
    port = int(os.getenv("PG_PORT", "5432"))
    db = os.getenv("PG_DB")
    user = os.getenv("PG_USER")
    password = os.getenv("PG_PASSWORD")

    if not all([host, db, user, password]):
        raise RuntimeError("Variabili PG_* mancanti nel file .env")

    conn = psycopg2.connect(
        host=host,
        port=port,
        dbname=db,
        user=user,
        password=password,
        sslmode="require",
        connect_timeout=20,
    )
    conn.autocommit = True
    return conn


def get_min_max_features(conn):
    with conn.cursor() as cur:
        cur.execute("""
            SELECT MIN(data)::date, MAX(data)::date
            FROM public.greenhouse_forecast_features_dense
        """)
        return cur.fetchone()


def patch_range(conn, start_d: date, end_d: date):
    with conn.cursor() as cur:
        cur.execute("SELECT set_config('statement_timeout', %s, true);", (str(STATEMENT_TIMEOUT_MS),))
        cur.execute("SELECT public.patch_features_holidays_range(%s::date, %s::date);", (start_d, end_d))


def main():
    p = load_progress()
    conn = db_connect()

    mn, mx = get_min_max_features(conn)
    if mn is None or mx is None:
        raise RuntimeError("greenhouse_forecast_features_dense è vuota: niente da patchare.")

    start_date = mn
    end_date = mx

    # riparti da progress se presente
    if "next_start" in p:
        try:
            ns = iso_to_date(p["next_start"])
            if start_date <= ns <= end_date:
                start_date = ns
        except Exception:
            pass

    print("🚀 Patch HOLIDAYS su greenhouse_forecast_features_dense")
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
                patch_range(conn, chunk_start, chunk_end)
                dt = time.time() - t0
                print(f"✅ OK ({dt:.1f}s)")

                p["last_ok_range"] = {"start": chunk_start.isoformat(), "end": chunk_end.isoformat(), "step_days": STEP_DAYS}
                p["next_start"] = (chunk_end + timedelta(days=1)).isoformat()
                p["last_error"] = None
                save_progress(p)

                ok = True
                break

            except Exception as e:
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
            return

        d = chunk_end + timedelta(days=1)

    print("\n🎉 PATCH HOLIDAYS COMPLETATA fino a:", end_date)
    print("Progress saved in:", os.path.abspath(PROGRESS_FILE))
    conn.close()


if __name__ == "__main__":
    main()