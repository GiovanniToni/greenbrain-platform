import os
import requests
from datetime import date

import psycopg2
from dotenv import load_dotenv


NAGER_URL = "https://date.nager.at/api/v3/PublicHolidays/{year}/IT"

START_YEAR = 2009


def db_connect():
    load_dotenv(".env")
    conn = psycopg2.connect(
        host=os.getenv("PG_HOST"),
        port=os.getenv("PG_PORT", "5432"),
        dbname=os.getenv("PG_DB"),
        user=os.getenv("PG_USER"),
        password=os.getenv("PG_PASSWORD"),
        sslmode="require",
        connect_timeout=20,
    )
    conn.autocommit = True
    return conn


def upsert_holiday(cur, d: str, name: str):
    cur.execute(
        """
        INSERT INTO public.greenhouse_holidays (data, is_holiday, holiday_name)
        VALUES (%s::date, true, %s)
        ON CONFLICT (data)
        DO UPDATE SET
          is_holiday = true,
          holiday_name = EXCLUDED.holiday_name,
          created_at = COALESCE(public.greenhouse_holidays.created_at, now());
        """,
        (d, name),
    )


def add_local_holidays(cur, year: int):
    # Firenze – San Giovanni (24 giugno)
    upsert_holiday(cur, f"{year}-06-24", "Firenze – San Giovanni (locale)")
    # Pistoia – San Jacopo (25 luglio)
    upsert_holiday(cur, f"{year}-07-25", "Pistoia – San Jacopo (locale)")


def main():
    today = date.today()
    end_year = today.year + 1  # utile per forecast

    conn = db_connect()
    try:
        with conn.cursor() as cur:
            total = 0
            for y in range(START_YEAR, end_year + 1):
                url = NAGER_URL.format(year=y)
                r = requests.get(url, timeout=30)
                r.raise_for_status()
                holidays = r.json()

                # Nager restituisce array di oggetti con date, localName, name, ecc.
                for h in holidays:
                    d = h.get("date")          # "YYYY-MM-DD"
                    nm = h.get("localName") or h.get("name") or "Holiday"
                    upsert_holiday(cur, d, nm)
                    total += 1

                # aggiungo locali
                add_local_holidays(cur, y)

                print(f"✅ {y}: inserite/aggiornate {len(holidays)} + 2 locali")

            print(f"\n🎉 DONE. Righe upsertate (circa): {total} (+ locali per anno)")
    finally:
        conn.close()


if __name__ == "__main__":
    main()