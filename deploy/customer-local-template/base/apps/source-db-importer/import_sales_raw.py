import os
import json
import time
import traceback
from datetime import datetime
from pathlib import Path

import pandas as pd
import pyodbc
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[3]
CUSTOMER_ENV = ROOT / "overlay/env/customer-local.env"
SOURCE_ENV = ROOT / "overlay/env/source-db.env"
LOG_DIR = ROOT / "overlay/logs/source-db"
LOG_DIR.mkdir(parents=True, exist_ok=True)

DEST_TABLE = "source_import.sales_raw"
SOURCE_CLIENT_CODE = os.getenv("SOURCE_CLIENT_CODE", "greenhouse")


def log(msg: str):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    with open(LOG_DIR / "source_db_import_latest.log", "a", encoding="utf-8") as f:
        f.write(line + "\n")


def load_envs():
    if not CUSTOMER_ENV.exists():
        raise RuntimeError(f"missing {CUSTOMER_ENV}")
    if not SOURCE_ENV.exists():
        raise RuntimeError(f"missing {SOURCE_ENV}")
    load_dotenv(CUSTOMER_ENV)
    load_dotenv(SOURCE_ENV, override=True)


def get_best_sql_driver():
    available = [d.strip() for d in pyodbc.drivers()]
    preferred = [
        "ODBC Driver 18 for SQL Server",
        "ODBC Driver 17 for SQL Server",
        "ODBC Driver 13 for SQL Server",
        "ODBC Driver 11 for SQL Server",
        "SQL Server",
    ]
    for drv in preferred:
        if drv in available:
            log(f"SQL Server ODBC driver: {drv}")
            return drv
    raise RuntimeError(f"No compatible SQL Server ODBC driver found. Available: {available}")


def sqlserver_connection():
    driver = get_best_sql_driver()
    host = os.getenv("SOURCE_DB_HOST")
    port = os.getenv("SOURCE_DB_PORT", "1433")
    db = os.getenv("SOURCE_DB_NAME")
    user = os.getenv("SOURCE_DB_USER")
    password = os.getenv("SOURCE_DB_PASSWORD")
    encrypt = os.getenv("SOURCE_DB_ENCRYPT", "false")
    trust_cert = os.getenv("SOURCE_DB_TRUST_CERT", "true")

    if not all([host, db, user, password]):
        raise RuntimeError("missing Source DB env values")

    conn_str = (
        f"DRIVER={{{driver}}};"
        f"SERVER={host},{port};"
        f"DATABASE={db};"
        f"UID={user};"
        f"PWD={password};"
        f"Encrypt={encrypt};"
        f"TrustServerCertificate={trust_cert};"
    )
    return pyodbc.connect(conn_str, timeout=10)


def pg_engine():
    pg_host = os.getenv("POSTGRES_HOST", "postgres")
    pg_port = os.getenv("POSTGRES_PORT", "5432")
    pg_db = os.getenv("POSTGRES_DB")
    pg_user = os.getenv("POSTGRES_USER")
    pg_password = os.getenv("POSTGRES_PASSWORD")

    if not all([pg_db, pg_user, pg_password]):
        raise RuntimeError("missing local Postgres env values")

    return create_engine(
        f"postgresql+psycopg2://{pg_user}:{pg_password}@{pg_host}:{pg_port}/{pg_db}"
    )


def get_last_progressivo(engine):
    with engine.connect() as conn:
        row = conn.execute(
            text("""
                SELECT COALESCE(MAX(progressivo), 0)
                FROM source_import.sales_raw
                WHERE source_client_code = :client
            """),
            {"client": SOURCE_CLIENT_CODE},
        ).fetchone()
    return int(row[0] or 0)


def extract_incremental(last_progressivo):
    query = f"""
    SELECT
        Progressivo,
        CodArt,
        DESCRIZIONE,
        TIPO,
        FASCIA,
        CATEGORIA,
        QUANTITA,
        IMPONIBILENETTO,
        DATA AS data_movimento,
        DISATTIVATO,
        MOVIM_CASSA
    FROM GREENHOUSE_VIEW_STAT
    WHERE
        MOVIM_CASSA = 1
        AND Progressivo > {int(last_progressivo)}
    """
    conn = sqlserver_connection()
    try:
        return pd.read_sql(query, conn)
    finally:
        conn.close()


def normalize(df: pd.DataFrame) -> pd.DataFrame:
    df = df.rename(columns={
        "Progressivo": "progressivo",
        "CodArt": "codart",
        "DESCRIZIONE": "descrizione",
        "TIPO": "tipo",
        "FASCIA": "fascia",
        "CATEGORIA": "categoria",
        "QUANTITA": "quantita",
        "IMPONIBILENETTO": "imponibilenetto",
        "DISATTIVATO": "disattivato",
        "MOVIM_CASSA": "movim_cassa",
    })

    for col in ["quantita", "imponibilenetto"]:
        if col in df.columns:
            df[col] = (
                df[col]
                .astype(str)
                .str.replace(",", ".", regex=False)
                .replace({"None": None, "nan": None})
            )
            df[col] = pd.to_numeric(df[col], errors="coerce")

    for col in ["disattivato", "movim_cassa"]:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0).astype(int)

    df["source_client_code"] = SOURCE_CLIENT_CODE
    df["load_timestamp"] = datetime.now()
    df["raw_payload"] = df.astype(str).apply(lambda row: json.dumps(row.to_dict(), ensure_ascii=False), axis=1)
    df = df.drop_duplicates(subset=["source_client_code", "progressivo"])

    cols = [
        "source_client_code", "progressivo", "codart", "descrizione", "tipo",
        "fascia", "categoria", "quantita", "imponibilenetto", "data_movimento",
        "disattivato", "movim_cassa", "load_timestamp", "raw_payload"
    ]
    return df[[c for c in cols if c in df.columns]]


def load_to_local_postgres(engine, df: pd.DataFrame):
    if df.empty:
        return 0

    tmp_table = "sales_raw_tmp_import"
    with engine.begin() as conn:
        df.to_sql(tmp_table, conn, schema="source_import", if_exists="replace", index=False, chunksize=5000)
        result = conn.execute(text("""
            INSERT INTO source_import.sales_raw (
              source_client_code, progressivo, codart, descrizione, tipo, fascia,
              categoria, quantita, imponibilenetto, data_movimento, disattivato,
              movim_cassa, load_timestamp, raw_payload
            )
            SELECT
              source_client_code, progressivo, codart, descrizione, tipo, fascia,
              categoria, quantita, imponibilenetto, data_movimento, disattivato,
              movim_cassa, load_timestamp, raw_payload::jsonb
            FROM source_import.sales_raw_tmp_import
            ON CONFLICT (source_client_code, progressivo) DO NOTHING
        """))
        conn.execute(text("DROP TABLE IF EXISTS source_import.sales_raw_tmp_import"))
        return result.rowcount if result.rowcount is not None else 0


def run():
    load_envs()
    log(f"Source DB import start | client={SOURCE_CLIENT_CODE}")

    engine = pg_engine()
    try:
        last_prog = get_last_progressivo(engine)
        log(f"Last progressivo local: {last_prog}")

        df = extract_incremental(last_prog)
        log(f"Rows extracted: {len(df)}")

        if df.empty:
            log("No new rows")
            return

        clean = normalize(df)
        inserted = load_to_local_postgres(engine, clean)
        log(f"Import completed | inserted={inserted}")
    finally:
        engine.dispose()


if __name__ == "__main__":
    max_retries = int(os.getenv("SOURCE_DB_IMPORT_RETRIES", "3"))
    for attempt in range(1, max_retries + 1):
        try:
            log(f"Attempt {attempt}/{max_retries}")
            run()
            break
        except Exception as e:
            log(f"ERROR attempt {attempt}: {e}")
            traceback.print_exc()
            if attempt >= max_retries:
                raise
            time.sleep(30)
