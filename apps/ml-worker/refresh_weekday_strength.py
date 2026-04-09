import os
import sys
import logging
from datetime import datetime

from sqlalchemy import create_engine, text
from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_PATH = os.path.join(BASE_DIR, ".env")
if os.path.exists(ENV_PATH):
    load_dotenv(ENV_PATH)

LOGS_DIR = os.path.join(BASE_DIR, "logs")
os.makedirs(LOGS_DIR, exist_ok=True)
LOG_PATH = os.path.join(LOGS_DIR, "refresh_weekday_strength.log")

STRENGTH_TABLE = "public.greenhouse_weekday_strength"
STRENGTH_FAMILY_TABLE = "public.greenhouse_weekday_strength_family"
SALES_TABLE = "public.greenhouse_sales_family_daily_v2"

# =========================
# SHRINKAGE CONFIG
# =========================
# weight = n_days / (n_days + K)
# strength_shrunk = 1 + weight * (strength_raw - 1)
SHRINK_K = int(os.getenv("STRENGTH_SHRINK_K", "30"))  # default 30


def get_engine():
    host = os.getenv("PG_HOST")
    port = os.getenv("PG_PORT", "5432")
    db = os.getenv("PG_DB")
    user = os.getenv("PG_USER")
    pwd = os.getenv("PG_PASSWORD")
    if not all([host, db, user, pwd]):
        raise RuntimeError("Variabili PG_* mancanti nel .env")
    return create_engine(
        f"postgresql+psycopg2://{user}:{pwd}@{host}:{port}/{db}?sslmode=require",
        pool_pre_ping=True,
    )


def setup_logger():
    logger = logging.getLogger("refresh_strength")
    logger.setLevel(logging.INFO)

    # evita doppio logging se rilanci in stesso processo
    if logger.handlers:
        return logger

    fmt = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")

    fh = logging.FileHandler(LOG_PATH)
    fh.setFormatter(fmt)
    logger.addHandler(fh)

    sh = logging.StreamHandler(sys.stdout)
    sh.setFormatter(fmt)
    logger.addHandler(sh)

    return logger


def main():
    logger = setup_logger()
    engine = get_engine()

    logger.info(f"=== START refresh_weekday_strength (SHRINK_K={SHRINK_K}) ===")

    # 1) Strength per FASCIA
    sql_truncate_fascia = text(f"TRUNCATE TABLE {STRENGTH_TABLE};")

    sql_insert_fascia = text(f"""
        INSERT INTO {STRENGTH_TABLE} (
          famiglia, fascia_prezzo_iva_inc, week_of_year, dow,
          avg_qty_dow, avg_qty_week, strength, n_days, updated_at
        )
        WITH base AS (
          SELECT
            LOWER(famiglia) AS famiglia,
            fascia_prezzo_iva_inc,
            EXTRACT(WEEK FROM data)::int AS week_of_year,
            EXTRACT(DOW  FROM data)::int AS dow,
            qty_venduta::numeric AS qty
          FROM {SALES_TABLE}
          WHERE data >= DATE '2009-01-01'
            AND data <= (CURRENT_DATE - INTERVAL '1 day')::date
        ),
        agg_dow AS (
          SELECT
            famiglia, fascia_prezzo_iva_inc, week_of_year, dow,
            AVG(qty) AS avg_qty_dow,
            COUNT(*) AS n_days
          FROM base
          GROUP BY 1,2,3,4
        ),
        agg_week AS (
          SELECT
            famiglia, fascia_prezzo_iva_inc, week_of_year,
            AVG(qty) AS avg_qty_week
          FROM base
          GROUP BY 1,2,3
        )
        SELECT
          d.famiglia,
          d.fascia_prezzo_iva_inc,
          d.week_of_year,
          d.dow,
          d.avg_qty_dow,
          w.avg_qty_week,

          -- strength con shrinkage
          CASE
            WHEN w.avg_qty_week > 0 THEN
              (
                1
                + (d.n_days::numeric / (d.n_days + :k)::numeric)
                  * ((d.avg_qty_dow / w.avg_qty_week) - 1)
              )
            ELSE 1
          END AS strength,

          d.n_days,
          now()
        FROM agg_dow d
        JOIN agg_week w
          ON w.famiglia = d.famiglia
         AND w.fascia_prezzo_iva_inc = d.fascia_prezzo_iva_inc
         AND w.week_of_year = d.week_of_year;
    """)

    # 2) Strength FAMILY (fallback senza fascia)
    sql_truncate_family = text(f"TRUNCATE TABLE {STRENGTH_FAMILY_TABLE};")

    sql_insert_family = text(f"""
        INSERT INTO {STRENGTH_FAMILY_TABLE} (
          famiglia, week_of_year, dow,
          avg_qty_dow, avg_qty_week, strength, n_days, updated_at
        )
        WITH base AS (
          SELECT
            LOWER(famiglia) AS famiglia,
            EXTRACT(WEEK FROM data)::int AS week_of_year,
            EXTRACT(DOW  FROM data)::int AS dow,
            qty_venduta::numeric AS qty
          FROM {SALES_TABLE}
          WHERE data >= DATE '2009-01-01'
            AND data <= (CURRENT_DATE - INTERVAL '1 day')::date
        ),
        agg_dow AS (
          SELECT
            famiglia, week_of_year, dow,
            AVG(qty) AS avg_qty_dow,
            COUNT(*) AS n_days
          FROM base
          GROUP BY 1,2,3
        ),
        agg_week AS (
          SELECT
            famiglia, week_of_year,
            AVG(qty) AS avg_qty_week
          FROM base
          GROUP BY 1,2
        )
        SELECT
          d.famiglia,
          d.week_of_year,
          d.dow,
          d.avg_qty_dow,
          w.avg_qty_week,

          -- strength con shrinkage
          CASE
            WHEN w.avg_qty_week > 0 THEN
              (
                1
                + (d.n_days::numeric / (d.n_days + :k)::numeric)
                  * ((d.avg_qty_dow / w.avg_qty_week) - 1)
              )
            ELSE 1
          END AS strength,

          d.n_days,
          now()
        FROM agg_dow d
        JOIN agg_week w
          ON w.famiglia = d.famiglia
         AND w.week_of_year = d.week_of_year;
    """)

    started = datetime.now()
    with engine.begin() as conn:
        logger.info("TRUNCATE + INSERT strength fascia (shrunk)...")
        conn.execute(sql_truncate_fascia)
        conn.execute(sql_insert_fascia, {"k": SHRINK_K})

        logger.info("TRUNCATE + INSERT strength family (shrunk)...")
        conn.execute(sql_truncate_family)
        conn.execute(sql_insert_family, {"k": SHRINK_K})

    elapsed = (datetime.now() - started).total_seconds()
    logger.info(f"=== DONE refresh_weekday_strength in {elapsed:.2f}s ===")

    engine.dispose()


if __name__ == "__main__":
    main()