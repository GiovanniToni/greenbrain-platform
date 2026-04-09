import os
import time
import traceback
from pathlib import Path

import pandas as pd
import pyodbc
from dotenv import load_dotenv
from sqlalchemy import create_engine, text


BASE_DIR = Path(__file__).resolve().parent
ENV_PATH = BASE_DIR / ".env"
load_dotenv(ENV_PATH)

JOB_NAME = "sqlserver_to_greenbrain_raw"


def env(name: str, default=None):
    return os.getenv(name, default)


SQLSERVER_SERVER = env("SQLSERVER_SERVER")
SQLSERVER_DB = env("SQLSERVER_DB")
SQLSERVER_USER = env("SQLSERVER_USER")
SQLSERVER_PASSWORD = env("SQLSERVER_PASSWORD")
SQLSERVER_DRIVER = env("SQLSERVER_DRIVER", "")
SQLSERVER_SOURCE_OBJECT = env("SQLSERVER_SOURCE_OBJECT", "GREENHOUSE_VIEW_STAT")

PG_HOST = env("PG_HOST", "127.0.0.1")
PG_PORT = env("PG_PORT", "55432")
PG_DB = env("PG_DB", "greenbrain")
PG_USER = env("PG_USER", "greenbrain")
PG_PASSWORD = env("PG_PASSWORD", "greenbrain")
PG_SSLMODE = env("PG_SSLMODE", "disable")

RUN_TYPE = env("RUN_TYPE", "incremental_daily")
FULL_BULK = env("FULL_BULK", "0").strip().lower() in ("1", "true", "yes", "y", "on")
BATCH_SIZE = int(env("BATCH_SIZE", "5000"))
MAX_RETRIES = int(env("MAX_RETRIES", "3"))


def get_best_sql_driver():
    if SQLSERVER_DRIVER.strip():
        return SQLSERVER_DRIVER.strip()

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
            return drv
    raise RuntimeError(f"Nessun driver SQL Server compatibile trovato. Disponibili: {available}")


def get_sqlserver_connection():
    driver = get_best_sql_driver()
    conn_str = (
        f"DRIVER={{{driver}}};"
        f"SERVER={SQLSERVER_SERVER};"
        f"DATABASE={SQLSERVER_DB};"
        f"UID={SQLSERVER_USER};"
        f"PWD={SQLSERVER_PASSWORD};"
        f"TrustServerCertificate=yes;"
    )
    return pyodbc.connect(conn_str)


def get_pg_engine():
    conn_str = (
        f"postgresql+psycopg2://{PG_USER}:{PG_PASSWORD}"
        f"@{PG_HOST}:{PG_PORT}/{PG_DB}"
    )
    connect_args = {}
    if PG_SSLMODE:
        connect_args["sslmode"] = PG_SSLMODE
    return create_engine(conn_str, connect_args=connect_args)


def get_last_progressivo(engine):
    with engine.begin() as conn:
        row = conn.execute(
            text("SELECT COALESCE(MAX(progressivo), 0) AS v FROM public.greenhouse_sales_raw")
        ).mappings().first()
    return int(row["v"])


def create_etl_run(engine, run_type, source_object, from_progressivo):
    with engine.begin() as conn:
        row = conn.execute(
            text("""
                INSERT INTO public.etl_runs (
                    job_name,
                    run_type,
                    status,
                    started_at,
                    source_system,
                    source_object,
                    from_progressivo,
                    meta_json
                )
                VALUES (
                    :job_name,
                    :run_type,
                    'running',
                    now(),
                    'sqlserver',
                    :source_object,
                    :from_progressivo,
                    '{}'::jsonb
                )
                RETURNING run_id
            """),
            {
                "job_name": JOB_NAME,
                "run_type": run_type,
                "source_object": source_object,
                "from_progressivo": from_progressivo,
            },
        ).mappings().first()
    return int(row["run_id"])


def mark_etl_run_success(engine, run_id, to_progressivo, rows_extracted, rows_loaded, rows_skipped):
    with engine.begin() as conn:
        conn.execute(
            text("""
                UPDATE public.etl_runs
                SET
                    status = 'success',
                    ended_at = now(),
                    to_progressivo = :to_progressivo,
                    rows_extracted = :rows_extracted,
                    rows_loaded = :rows_loaded,
                    rows_skipped = :rows_skipped
                WHERE run_id = :run_id
            """),
            {
                "run_id": run_id,
                "to_progressivo": to_progressivo,
                "rows_extracted": rows_extracted,
                "rows_loaded": rows_loaded,
                "rows_skipped": rows_skipped,
            },
        )


def mark_etl_run_failed(engine, run_id, error_message):
    with engine.begin() as conn:
        conn.execute(
            text("""
                UPDATE public.etl_runs
                SET
                    status = 'failed',
                    ended_at = now(),
                    error_message = :error_message
                WHERE run_id = :run_id
            """),
            {
                "run_id": run_id,
                "error_message": error_message[:4000],
            },
        )


def extract_sqlserver(last_progressivo):
    if FULL_BULK:
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
        FROM {SQLSERVER_SOURCE_OBJECT}
        WHERE MOVIM_CASSA = 1
        """
    else:
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
        FROM {SQLSERVER_SOURCE_OBJECT}
        WHERE MOVIM_CASSA = 1
          AND Progressivo > {last_progressivo}
        """

    conn = get_sqlserver_connection()
    try:
        return pd.read_sql(query, conn)
    finally:
        conn.close()


def normalize_df(df: pd.DataFrame) -> pd.DataFrame:
    if df.empty:
        return df

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
    }).copy()

    for col in ["quantita", "imponibilenetto"]:
        if col in df.columns:
            df[col] = (
                df[col]
                .astype(str)
                .str.replace(",", ".", regex=False)
                .replace({"None": None, "nan": None, "": None})
            )
            df[col] = pd.to_numeric(df[col], errors="coerce")

    for col in ["disattivato", "movim_cassa"]:
        if col in df.columns:
            df[col] = df[col].fillna(0).astype(int)

    df["load_timestamp"] = pd.Timestamp.now()
    df = df.drop_duplicates(subset=["progressivo"])
    return df


def load_staging(engine, df: pd.DataFrame):
    with engine.begin() as conn:
        conn.execute(text("TRUNCATE TABLE public.greenhouse_sales_raw_staging"))

    df.to_sql(
        "greenhouse_sales_raw_staging",
        engine,
        schema="public",
        if_exists="append",
        index=False,
        chunksize=BATCH_SIZE,
        method="multi",
    )


def merge_staging_to_raw(engine):
    with engine.begin() as conn:
        row = conn.execute(
            text("SELECT * FROM public.merge_greenhouse_sales_raw_from_staging()")
        ).mappings().first()
    return int(row["inserted_count"]), int(row["updated_count"])


def sync_products(engine):
    with engine.begin() as conn:
        row = conn.execute(
            text("SELECT * FROM public.sync_products_normalized_from_raw()")
        ).mappings().first()
    return int(row["inserted_count"]), int(row["updated_count"])


def run_once():
    engine = get_pg_engine()
    run_id = None

    try:
        last_progressivo = 0 if FULL_BULK else get_last_progressivo(engine)
        run_id = create_etl_run(
            engine=engine,
            run_type=("bulk_initial" if FULL_BULK else RUN_TYPE),
            source_object=SQLSERVER_SOURCE_OBJECT,
            from_progressivo=last_progressivo,
        )

        print(f"[RUN {run_id}] start last_progressivo={last_progressivo} full_bulk={FULL_BULK}")

        df = extract_sqlserver(last_progressivo)
        df = normalize_df(df)

        rows_extracted = len(df)
        print(f"[RUN {run_id}] extracted={rows_extracted}")

        if df.empty:
            mark_etl_run_success(
                engine=engine,
                run_id=run_id,
                to_progressivo=last_progressivo,
                rows_extracted=0,
                rows_loaded=0,
                rows_skipped=0,
            )
            print(f"[RUN {run_id}] no new rows")
            return

        load_staging(engine, df)
        inserted, updated = merge_staging_to_raw(engine)
        p_ins, p_upd = sync_products(engine)

        to_progressivo = int(df["progressivo"].max())
        rows_loaded = inserted + updated
        rows_skipped = max(rows_extracted - rows_loaded, 0)

        with engine.begin() as conn:
            conn.execute(
                text("""
                    UPDATE public.etl_runs
                    SET
                        meta_json = jsonb_build_object(
                            'raw_inserted', :raw_inserted,
                            'raw_updated', :raw_updated,
                            'products_inserted', :products_inserted,
                            'products_updated', :products_updated
                        )
                    WHERE run_id = :run_id
                """),
                {
                    "run_id": run_id,
                    "raw_inserted": inserted,
                    "raw_updated": updated,
                    "products_inserted": p_ins,
                    "products_updated": p_upd,
                },
            )

        mark_etl_run_success(
            engine=engine,
            run_id=run_id,
            to_progressivo=to_progressivo,
            rows_extracted=rows_extracted,
            rows_loaded=rows_loaded,
            rows_skipped=rows_skipped,
        )

        print(
            f"[RUN {run_id}] success extracted={rows_extracted} "
            f"raw_inserted={inserted} raw_updated={updated} "
            f"products_inserted={p_ins} products_updated={p_upd}"
        )

    except Exception as e:
        print(f"[ERROR] {e}")
        traceback.print_exc()
        if run_id is not None:
            try:
                mark_etl_run_failed(engine, run_id, str(e))
            except Exception:
                traceback.print_exc()
        raise
    finally:
        engine.dispose()


if __name__ == "__main__":
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            print(f"[INFO] attempt {attempt}/{MAX_RETRIES}")
            run_once()
            break
        except Exception as e:
            if attempt >= MAX_RETRIES:
                print(f"[FATAL] ETL failed after {MAX_RETRIES} attempts: {e}")
                raise
            wait_sec = 30
            print(f"[WARN] retry in {wait_sec}s")
            time.sleep(wait_sec)
