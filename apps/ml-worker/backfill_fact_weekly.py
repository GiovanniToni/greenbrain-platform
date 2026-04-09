import os
import json
import time
from datetime import date, datetime, timedelta

import psycopg2
from psycopg2.extras import execute_values
from dotenv import load_dotenv

# ================= CONFIG =================
PROGRESS_FILE = "backfill_fact_progress.json"

# chunk sizes (fallback automatico)
STEP_CANDIDATES = [7, 3, 1]

MAX_RETRIES = 3
RETRY_SLEEP_SEC = 10
SLEEP_BETWEEN_CALLS_SEC = 0

# Range completo (puoi cambiarli se vuoi)
START_DATE_DEFAULT = "2009-01-02"
END_DATE_DEFAULT = "2026-01-08"

# Se vuoi forzare un range specifico (opzionale)
FORCE_START = None  # es: "2019-01-01"
FORCE_END = None    # es: "2019-12-31"
# =========================================


UPSERT_SQL = """
INSERT INTO public.greenhouse_sales_family_daily_fact (
  data, famiglia, fascia_prezzo_iva_inc,
  qty_venduta, imponibile_netto_tot, num_articoli,
  fascia_corretta, categoria_corretta,
  pot_sizes_text, pot_sizes_json,
  articoli_inclusi, articoli_json
)
SELECT
  data, famiglia, fascia_prezzo_iva_inc,
  qty_venduta, imponibile_netto_tot, num_articoli,
  fascia_corretta, categoria_corretta,
  pot_sizes_text,
  COALESCE(pot_sizes_json::jsonb, '[]'::jsonb) AS pot_sizes_json,
  articoli_inclusi,
  COALESCE(articoli_json::jsonb, '[]'::jsonb) AS articoli_json
FROM public.greenhouse_sales_family_daily_v2
WHERE data BETWEEN %s AND %s
ON CONFLICT (data, famiglia, fascia_prezzo_iva_inc) DO UPDATE SET
  qty_venduta = EXCLUDED.qty_venduta,
  imponibile_netto_tot = EXCLUDED.imponibile_netto_tot,
  num_articoli = EXCLUDED.num_articoli,
  fascia_corretta = EXCLUDED.fascia_corretta,
  categoria_corretta = EXCLUDED.categoria_corretta,
  pot_sizes_text = EXCLUDED.pot_sizes_text,
  pot_sizes_json = EXCLUDED.pot_sizes_json,
  articoli_inclusi = EXCLUDED.articoli_inclusi,
  articoli_json = EXCLUDED.articoli_json;
"""


def iso_to_date(s: str) -> date:
    return datetime.strptime(s, "%Y-%m-%d").date()


def load_progress() -> dict:
    if os.path.exists(PROGRESS_FILE):
        with open(PROGRESS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_progress(p: dict) -> None:
    with open(PROGRESS_FILE, "w", encoding="utf-8") as f:
        json.dump(p, f, ensure_ascii=False, indent=2)


def db_connect():
    load_dotenv()
    host = os.getenv("PG_HOST")
    port = int(os.getenv("PG_PORT", "5432"))
    db = os.getenv("PG_DB")
    user = os.getenv("PG_USER")
    pwd = os.getenv("PG_PASSWORD")

    if not all([host, db, user, pwd]):
        raise RuntimeError("❌ Variabili .env mancanti (PG_HOST/PG_DB/PG_USER/PG_PASSWORD).")

    conn = psycopg2.connect(
        host=host, port=port, dbname=db, user=user, password=pwd,
        connect_timeout=20,
        options="-c statement_timeout=120000"  # 120s lato server (puoi alzare)
    )
    conn.autocommit = True
    return conn


def upsert_fact_range(conn, start_d: date, end_d: date):
    with conn.cursor() as cur:
        cur.execute(UPSERT_SQL, (start_d, end_d))


def main():
    # range
    start_date = iso_to_date(FORCE_START) if FORCE_START else iso_to_date(START_DATE_DEFAULT)
    end_date = iso_to_date(FORCE_END) if FORCE_END else iso_to_date(END_DATE_DEFAULT)

    # progress
    p = load_progress()
    next_start = iso_to_date(p["next_start"]) if "next_start" in p else start_date

    if next_start < start_date:
        next_start = start_date
    if next_start > end_date:
        print("✅ Nulla da fare: progress già oltre la data finale.")
        return

    print(f"🚀 Backfill FACT weekly from: {next_start} to: {end_date}")
    print(f"📌 Progress file: {os.path.abspath(PROGRESS_FILE)}")
    print("🧱 Target table: public.greenhouse_sales_family_daily_fact")
    print("📚 Source: public.greenhouse_sales_family_daily_v2")

    conn = db_connect()

    try:
        d = next_start
        while d <= end_date:
            success = False
            last_exc = None

            for step_days in STEP_CANDIDATES:
                start_d = d
                end_d = min(end_date, start_d + timedelta(days=step_days - 1))

                for attempt in range(1, MAX_RETRIES + 1):
                    try:
                        print(f"\n➡️  Range {start_d} → {end_d}  (step={step_days}d)  attempt {attempt}/{MAX_RETRIES}")
                        t0 = time.time()
                        upsert_fact_range(conn, start_d, end_d)
                        dt = time.time() - t0
                        print(f"✅ OK ({dt:.1f}s)")

                        # update progress
                        next_start = end_d + timedelta(days=1)
                        p["next_start"] = next_start.isoformat()
                        p["last_ok_range"] = {"start": start_d.isoformat(), "end": end_d.isoformat(), "step_days": step_days}
                        p["last_error"] = None
                        save_progress(p)

                        if SLEEP_BETWEEN_CALLS_SEC:
                            time.sleep(SLEEP_BETWEEN_CALLS_SEC)

                        d = next_start
                        success = True
                        break

                    except Exception as e:
                        last_exc = e
                        msg = f"{type(e).__name__}: {e}"
                        print(f"❌ ERROR: {msg}")

                        p["last_error"] = {
                            "range": {"start": start_d.isoformat(), "end": end_d.isoformat(), "step_days": step_days},
                            "attempt": attempt,
                            "error": msg
                        }
                        save_progress(p)

                        if attempt < MAX_RETRIES:
                            print(f"⏳ retry in {RETRY_SLEEP_SEC}s...")
                            time.sleep(RETRY_SLEEP_SEC)

                if success:
                    break

                print(f"⚠️  chunk failed with step={step_days}d → trying smaller chunk...")

            if not success:
                print("\n🛑 STOP: anche 1 giorno continua a fallire.")
                print("Last error:", repr(last_exc))
                print("Progress saved in:", os.path.abspath(PROGRESS_FILE))
                return

        print("\n🎉 Backfill FACT COMPLETATO fino a:", end_date)
        print("Progress saved in:", os.path.abspath(PROGRESS_FILE))

    finally:
        conn.close()


if __name__ == "__main__":
    main()
