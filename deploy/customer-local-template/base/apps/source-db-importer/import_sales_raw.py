import os
import json
import time
import traceback
from datetime import datetime
from pathlib import Path

def _source_db_env_value(key):
    try:
        source_env = Path(__file__).resolve().parents[3] / "overlay/env/source-db.env"
        if not source_env.exists():
            return None
        prefix = key + "="
        for line in source_env.read_text(encoding="utf-8").splitlines():
            clean = line.strip()
            if not clean or clean.startswith("#") or "=" not in clean:
                continue
            if clean.startswith(prefix):
                return clean.split("=", 1)[1].strip()
    except Exception:
        return None
    return None


def configure_legacy_openssl_for_sqlserver():
    """Apply process-local OpenSSL compatibility only when explicitly enabled.

    Enable with SOURCE_DB_ODBC_LEGACY_TLS=yes for old on-prem SQL Servers
    that fail with ODBC Driver 18 and "SSL Provider: unsupported protocol".
    """
    mode = str(
        os.getenv("SOURCE_DB_ODBC_LEGACY_TLS")
        or _source_db_env_value("SOURCE_DB_ODBC_LEGACY_TLS")
        or "no"
    ).strip().lower()
    if mode not in ("1", "true", "yes", "y", "on", "enabled"):
        return False

    path = Path(os.getenv("SOURCE_DB_OPENSSL_CONF", "/tmp/greenbrain_openssl_legacy.cnf"))
    path.write_text(
        """openssl_conf = openssl_init

[openssl_init]
ssl_conf = ssl_sect

[ssl_sect]
system_default = system_default_sect

[system_default_sect]
MinProtocol = TLSv1
CipherString = DEFAULT@SECLEVEL=0
""",
        encoding="utf-8",
    )
    os.environ.setdefault("OPENSSL_CONF", str(path))
    return True


OPENSSL_LEGACY_CONF_APPLIED = configure_legacy_openssl_for_sqlserver()

import pyodbc

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[3]
CUSTOMER_ENV = ROOT / "overlay/env/customer-local.env"
SOURCE_ENV = ROOT / "overlay/env/source-db.env"
LOG_DIR = ROOT / "overlay/logs/source-db"
LOG_DIR.mkdir(parents=True, exist_ok=True)

DEST_TABLE = "source_import.sales_raw"



def source_client_code() -> str:
    return (
        os.getenv("SOURCE_DB_CLIENT_CODE")
        or os.getenv("SOURCE_CLIENT_CODE")
        or os.getenv("TENANT_CODE")
        or os.getenv("CUSTOMER_TENANT_CODE")
        or "greenbrain"
    )


def _env_int(name: str, default: int, *, minimum: int = 0) -> int:
    raw = os.getenv(name, str(default))
    try:
        value = int(str(raw).strip())
    except Exception:
        value = default
    return max(minimum, value)


def source_import_batch_size() -> int:
    return _env_int("SOURCE_DB_IMPORT_BATCH_SIZE", 50000, minimum=1)


def source_import_max_batches() -> int:
    # 0 means unlimited; useful for production/full import.
    # 1 or N is useful for smoke tests and controlled partial imports.
    return _env_int("SOURCE_DB_IMPORT_MAX_BATCHES", 0, minimum=0)

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



def normalize_odbc_bool(value, *, true_value="yes", false_value="no"):
    v = str(value or "").strip().lower()
    if v in ("1", "true", "yes", "y", "on"):
        return true_value
    if v in ("0", "false", "no", "n", "off"):
        return false_value
    if v in ("optional", "mandatory", "strict"):
        return v
    return value


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
            log(f"OpenSSL legacy TLS compatibility: {OPENSSL_LEGACY_CONF_APPLIED}")
            return drv
    raise RuntimeError(f"No compatible SQL Server ODBC driver found. Available: {available}")


def quote_sqlserver_identifier(value: str) -> str:
    clean = str(value or "").strip()
    if not clean:
        raise RuntimeError("empty SQL Server identifier")
    return "[" + clean.replace("]", "]]") + "]"


def source_sales_view_name() -> str:
    schema = os.getenv("SOURCE_DB_SCHEMA", "dbo")
    view = os.getenv("SOURCE_DB_VIEW", "GREENBRAIN_VIEW_SALES_RAW")
    return f"{quote_sqlserver_identifier(schema)}.{quote_sqlserver_identifier(view)}"




SOURCE_COLUMN_CANDIDATES = {
    "progressivo": ["progressivo", "Progressivo"],
    "codart": ["codart", "CodArt"],
    "descrizione": ["descrizione", "DESCRIZIONE"],
    "tipo": ["tipo", "TIPO"],
    "fascia": ["fascia", "FASCIA"],
    "categoria": ["categoria", "CATEGORIA"],
    "quantita": ["quantita", "QUANTITA"],
    "imponibile_netto": ["imponibile_netto", "IMPONIBILENETTO"],
    "data_movimento": ["data_movimento", "DATA"],
    "disattivato": ["disattivato", "DISATTIVATO"],
    "movim_cassa": ["movim_cassa", "MOVIM_CASSA"],
}

REQUIRED_IMPORT_COLUMNS = [
    "progressivo",
    "codart",
    "descrizione",
    "quantita",
    "imponibile_netto",
    "data_movimento",
]

OPTIONAL_IMPORT_COLUMNS = [
    "tipo",
    "fascia",
    "categoria",
    "disattivato",
    "movim_cassa",
]


def normalize_column_key(value: str) -> str:
    return str(value or "").strip().strip("[]").lower()


def fetch_source_columns(conn, source_view: str):
    cursor = conn.cursor()
    cursor.execute(f"SELECT TOP 0 * FROM {source_view}")
    return [col[0] for col in cursor.description or []]


def pick_source_column(columns, candidates, *, required=False, logical_name=""):
    lookup = {normalize_column_key(col): col for col in columns}
    for candidate in candidates:
        found = lookup.get(normalize_column_key(candidate))
        if found:
            return found
    if required:
        raise RuntimeError(f"missing_import_required_columns:{logical_name}")
    return None



def build_source_select_query(source_view: str, columns, last_progressivo: int, batch_size: int):
    resolved = {}
    missing = []

    for logical in REQUIRED_IMPORT_COLUMNS:
        try:
            resolved[logical] = pick_source_column(
                columns,
                SOURCE_COLUMN_CANDIDATES[logical],
                required=True,
                logical_name=logical,
            )
        except RuntimeError:
            missing.append(logical)

    if missing:
        raise RuntimeError("missing_import_required_columns:" + ",".join(missing))

    for logical in OPTIONAL_IMPORT_COLUMNS:
        found = pick_source_column(
            columns,
            SOURCE_COLUMN_CANDIDATES[logical],
            required=False,
            logical_name=logical,
        )
        if found:
            resolved[logical] = found

    select_parts = []
    for logical, source_col in resolved.items():
        select_parts.append(
            f"{quote_sqlserver_identifier(source_col)} AS {quote_sqlserver_identifier(logical)}"
        )

    progressivo_col = quote_sqlserver_identifier(resolved["progressivo"])
    where_parts = [f"{progressivo_col} > {int(last_progressivo)}"]

    if resolved.get("movim_cassa"):
        movim_col = quote_sqlserver_identifier(resolved["movim_cassa"])
        where_parts.append(f"{movim_col} = 1")

    safe_batch_size = max(1, int(batch_size))

    query = (
        f"SELECT TOP ({safe_batch_size})\n        "
        + ",\n        ".join(select_parts)
        + f"\n    FROM {source_view}\n    WHERE\n        "
        + "\n        AND ".join(where_parts)
        + f"\n    ORDER BY {progressivo_col}"
    )

    return query, resolved

def sqlserver_connection():
    driver = get_best_sql_driver()
    host = os.getenv("SOURCE_DB_HOST")
    port = os.getenv("SOURCE_DB_PORT", "1433")
    db = os.getenv("SOURCE_DB_NAME")
    user = os.getenv("SOURCE_DB_USER")
    password = os.getenv("SOURCE_DB_PASSWORD")
    encrypt = normalize_odbc_bool(os.getenv("SOURCE_DB_ENCRYPT", "no"))
    trust_cert = normalize_odbc_bool(os.getenv("SOURCE_DB_TRUST_CERT", "yes"))

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
            {"client": source_client_code()},
        ).fetchone()
    return int(row[0] or 0)



def extract_incremental(last_progressivo, batch_size: int):
    source_view = source_sales_view_name()
    conn = sqlserver_connection()
    try:
        columns = fetch_source_columns(conn, source_view)
        query, resolved_columns = build_source_select_query(source_view, columns, last_progressivo, batch_size)
        log(
            "Source DB columns resolved: "
            + ", ".join(f"{logical}={source}" for logical, source in resolved_columns.items())
        )
        return pd.read_sql(query, conn)
    finally:
        conn.close()

def normalize(df: pd.DataFrame) -> pd.DataFrame:
    df = df.rename(columns={
        # Legacy FLORINFO / GREENHOUSE_VIEW_STAT names
        "Progressivo": "progressivo",
        "CodArt": "codart",
        "DESCRIZIONE": "descrizione",
        "TIPO": "tipo",
        "FASCIA": "fascia",
        "CATEGORIA": "categoria",
        "QUANTITA": "quantita",
        "IMPONIBILENETTO": "imponibile_netto",
        "DATA": "data_movimento",
        "DISATTIVATO": "disattivato",
        "MOVIM_CASSA": "movim_cassa",
        # Standard GREENBRAIN_VIEW_SALES_RAW names are already lower-case.
        "imponibile_netto": "imponibile_netto",
    })

    if "imponibile_netto" in df.columns and "imponibilenetto" not in df.columns:
        df["imponibilenetto"] = df["imponibile_netto"]

    required_normalized = [
        "progressivo",
        "codart",
        "descrizione",
        "quantita",
        "imponibilenetto",
        "data_movimento",
    ]
    missing = [col for col in required_normalized if col not in df.columns]
    if missing:
        raise RuntimeError("missing_normalized_import_columns:" + ",".join(missing))

    for col in ["tipo", "fascia", "categoria"]:
        if col not in df.columns:
            df[col] = None

    for col in ["disattivato", "movim_cassa"]:
        if col not in df.columns:
            df[col] = 0

    df["progressivo"] = pd.to_numeric(df["progressivo"], errors="coerce")
    df = df.dropna(subset=["progressivo"])
    df["progressivo"] = df["progressivo"].astype("int64")

    for col in ["quantita", "imponibilenetto"]:
        if col in df.columns:
            df[col] = (
                df[col]
                .astype(str)
                .str.replace(",", ".", regex=False)
                .replace({"None": None, "nan": None, "NaT": None})
            )
            df[col] = pd.to_numeric(df[col], errors="coerce")

    for col in ["disattivato", "movim_cassa"]:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0).astype(int)

    if "data_movimento" in df.columns:
        df["data_movimento"] = pd.to_datetime(df["data_movimento"], errors="coerce")

    df["source_client_code"] = source_client_code()
    df["load_timestamp"] = datetime.now()
    df["raw_payload"] = df.astype(str).apply(lambda row: json.dumps(row.to_dict(), ensure_ascii=False), axis=1)
    df = df.drop_duplicates(subset=["source_client_code", "progressivo"])

    cols = [
        "source_client_code", "progressivo", "codart", "descrizione", "tipo",
        "fascia", "categoria", "quantita", "imponibilenetto", "data_movimento",
        "disattivato", "movim_cassa", "load_timestamp", "raw_payload"
    ]
    return df[cols]

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
    batch_size = source_import_batch_size()
    max_batches = source_import_max_batches()

    log(
        f"Source DB import start | client={source_client_code()} | "
        f"view={source_sales_view_name()} | batch_size={batch_size} | "
        f"max_batches={max_batches or 'unlimited'}"
    )

    engine = pg_engine()
    total_extracted = 0
    total_inserted = 0
    batches = 0

    try:
        last_prog = get_last_progressivo(engine)
        log(f"Last progressivo local: {last_prog}")

        while True:
            if max_batches and batches >= max_batches:
                log(f"Max batches reached | max_batches={max_batches}")
                break

            batches += 1
            log(f"Batch {batches} start | last_progressivo={last_prog}")

            df = extract_incremental(last_prog, batch_size)
            extracted = len(df)
            total_extracted += extracted
            log(f"Batch {batches} rows extracted: {extracted}")

            if df.empty:
                log("No new rows")
                break

            clean = normalize(df)
            if clean.empty:
                log(f"Batch {batches} normalized rows empty; stopping to avoid infinite loop")
                break

            batch_max_progressivo = int(clean["progressivo"].max())

            inserted = load_to_local_postgres(engine, clean)
            total_inserted += inserted

            if batch_max_progressivo <= last_prog:
                log(
                    f"Batch {batches} did not advance progressivo "
                    f"({batch_max_progressivo} <= {last_prog}); stopping"
                )
                break

            last_prog = batch_max_progressivo
            log(
                f"Batch {batches} completed | inserted={inserted} | "
                f"new_last_progressivo={last_prog}"
            )

            if extracted < batch_size:
                log(f"Final batch reached | rows_extracted={extracted} < batch_size={batch_size}")
                break

        log(
            f"Import completed | batches={batches} | "
            f"extracted={total_extracted} | inserted={total_inserted}"
        )
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
