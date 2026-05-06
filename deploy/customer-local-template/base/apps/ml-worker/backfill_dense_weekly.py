import os
import json
import time
from datetime import date, timedelta, datetime

import psycopg2
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv

# ====== CONFIG ======
PROGRESS_FILE = "backfill_progress.json"
SLEEP_BETWEEN_CALLS_SEC = 1.0

# retry policy
MAX_RETRIES = 3
RETRY_SLEEP_SEC = 10

# default range (change if you want)
DEFAULT_START = date(2009, 1, 2)
DEFAULT_END   = date(2026, 1, 8)  # inclusive

# step sizes (days): try 7, if fail -> 3, if fail -> 1
STEP_CANDIDATES = [7, 3, 1]


def load_progress():
    if os.path.exists(PROGRESS_FILE):
        with open(PROGRESS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {
        "next_start": DEFAULT_START.isoformat(),
        "end": DEFAULT_END.isoformat(),
        "last_ok_range": None,
        "last_error": None,
        "updated_at": None,
    }


def save_progress(p):
    p["updated_at"] = datetime.now().isoformat(timespec="seconds")
    with open(PROGRESS_FILE, "w", encoding="utf-8") as f:
        json.dump(p, f, indent=2)


def get_conn():
    # reads your existing .env (PG_HOST, PG_PORT, PG_DB, PG_USER, PG_PASSWORD)
    load_dotenv()
    host = os.getenv("PG_HOST")
    port = int(os.getenv("PG_PORT", "5432"))
    db   = os.getenv("PG_DB")
    user = os.getenv("PG_USER")
    pwd  = os.getenv("PG_PASSWORD")

    if not all([host, db, user, pwd]):
        raise RuntimeError("Missing PG_* env vars. Check your .env file.")

    return psycopg2.connect(
        host=host,
        port=port,
        dbname=db,
        user=user,
        password=pwd,
        sslmode="require",
        connect_timeout=20,
    )


def call_refresh_dense_range(start_d: date, end_d: date):
    """
    Calls: SELECT public.refresh_dense_range('YYYY-MM-DD','YYYY-MM-DD');
    Uses a fresh connection each call to avoid long transactions.
    """
    conn = get_conn()
    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT public.refresh_dense_range(%s::date, %s::date);",
                (start_d.isoformat(), end_d.isoformat()),
            )
    finally:
        conn.close()


def main():
    p = load_progress()
    next_start = date.fromisoformat(p["next_start"])
    end_date   = date.fromisoformat(p["end"])

    if next_start > end_date:
        print("✅ Backfill già completato (next_start > end).")
        return

    print("🚀 Backfill weekly starting from:", next_start, "to:", end_date)
    print("📌 Progress file:", os.path.abspath(PROGRESS_FILE))

    while next_start <= end_date:
        # choose best step size
        success = False
        last_exc = None

        for step_days in STEP_CANDIDATES:
            start_d = next_start
            end_d = min(end_date, start_d + timedelta(days=step_days - 1))

            # retries for this chunk
            for attempt in range(1, MAX_RETRIES + 1):
                try:
                    print(f"\n➡️  Range {start_d} → {end_d}  (step={step_days}d)  attempt {attempt}/{MAX_RETRIES}")
                    t0 = time.time()
                    call_refresh_dense_range(start_d, end_d)
                    dt = time.time() - t0
                    print(f"✅ OK  ({dt:.1f}s)")

                    p["last_ok_range"] = {"start": start_d.isoformat(), "end": end_d.isoformat(), "step_days": step_days}
                    p["last_error"] = None

                    # advance pointer
                    next_start = end_d + timedelta(days=1)
                    p["next_start"] = next_start.isoformat()
                    save_progress(p)

                    time.sleep(SLEEP_BETWEEN_CALLS_SEC)
                    success = True
                    break

                except Exception as e:
                    last_exc = e
                    msg = f"{type(e).__name__}: {e}"
                    print(f"❌ ERROR: {msg}")
                    p["last_error"] = {"range": {"start": start_d.isoformat(), "end": end_d.isoformat(), "step_days": step_days},
                                       "attempt": attempt,
                                       "error": msg}
                    save_progress(p)

                    if attempt < MAX_RETRIES:
                        print(f"⏳ retry in {RETRY_SLEEP_SEC}s...")
                        time.sleep(RETRY_SLEEP_SEC)

            if success:
                break

            # if chunk failed with step_days, fall back to smaller step
            if not success:
                print(f"⚠️  chunk failed with step={step_days}d → trying smaller chunk...")

        if not success:
            # even 1-day chunk failed repeatedly -> stop safely
            print("\n🛑 STOP: even 1-day chunks keep failing.")
            print("Last error:", repr(last_exc))
            print("Progress saved in:", os.path.abspath(PROGRESS_FILE))
            return

    print("\n🎉 Backfill COMPLETATO fino a:", end_date)
    print("Progress saved in:", os.path.abspath(PROGRESS_FILE))


if __name__ == "__main__":
    main()
