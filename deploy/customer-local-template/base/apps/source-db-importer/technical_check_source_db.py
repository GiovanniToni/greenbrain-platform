import json
import os
import traceback
from datetime import datetime, timezone
from pathlib import Path

import pyodbc
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[3]
CUSTOMER_ENV = ROOT / "overlay/env/customer-local.env"
SOURCE_ENV = ROOT / "overlay/env/source-db.env"
LOG_DIR = ROOT / "overlay/logs/source-db"
LOG_DIR.mkdir(parents=True, exist_ok=True)

REQUIRED_COLUMNS = {
    "progressivo",
    "codart",
    "descrizione",
    "quantita",
    "imponibile_netto",
    "data_movimento",
}

RECOMMENDED_COLUMNS = {
    "tipo",
    "fascia",
    "categoria",
    "disattivato",
    "movim_cassa",
}


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def write_report(report):
    path_ts = LOG_DIR / f"technical_check_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.json"
    path_latest = LOG_DIR / "technical_check_latest.json"
    for path in (path_ts, path_latest):
        path.write_text(json.dumps(report, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    return path_latest


def quote_sqlserver_identifier(value):
    clean = str(value or "").strip()
    if not clean:
        raise RuntimeError("empty_sqlserver_identifier")
    return "[" + clean.replace("]", "]]") + "]"


def normalize_odbc_bool(value, true_value="yes", false_value="no"):
    v = str(value or "").strip().lower()
    if v in ("1", "true", "yes", "y", "on"):
        return true_value
    if v in ("0", "false", "no", "n", "off"):
        return false_value
    if v in ("optional", "mandatory", "strict"):
        return v
    return value


def load_envs():
    if CUSTOMER_ENV.exists():
        load_dotenv(CUSTOMER_ENV)
    if not SOURCE_ENV.exists():
        raise RuntimeError(f"missing_source_db_env:{SOURCE_ENV}")
    load_dotenv(SOURCE_ENV, override=True)


def source_view_name():
    schema = os.getenv("SOURCE_DB_SCHEMA", "dbo")
    view = os.getenv("SOURCE_DB_VIEW", "GREENBRAIN_VIEW_SALES_RAW")
    return f"{quote_sqlserver_identifier(schema)}.{quote_sqlserver_identifier(view)}"


def best_driver():
    available = [d.strip() for d in pyodbc.drivers()]
    preferred = [
        "ODBC Driver 18 for SQL Server",
        "ODBC Driver 17 for SQL Server",
        "ODBC Driver 13 for SQL Server",
        "ODBC Driver 11 for SQL Server",
        "SQL Server",
    ]
    for driver in preferred:
        if driver in available:
            return driver, available
    raise RuntimeError(f"no_compatible_sqlserver_odbc_driver:{available}")


def sqlserver_connection():
    driver, available = best_driver()
    host = os.getenv("SOURCE_DB_HOST")
    port = os.getenv("SOURCE_DB_PORT", "1433")
    db_name = os.getenv("SOURCE_DB_NAME")
    user = os.getenv("SOURCE_DB_USER")
    password = os.getenv("SOURCE_DB_PASSWORD")
    encrypt = normalize_odbc_bool(os.getenv("SOURCE_DB_ENCRYPT", "no"))
    trust_cert = normalize_odbc_bool(os.getenv("SOURCE_DB_TRUST_CERT", "yes"))

    missing = []
    for key, value in {
        "SOURCE_DB_HOST": host,
        "SOURCE_DB_NAME": db_name,
        "SOURCE_DB_USER": user,
        "SOURCE_DB_PASSWORD": password,
    }.items():
        if not str(value or "").strip():
            missing.append(key)
    if missing:
        raise RuntimeError("missing_source_db_env_values:" + ",".join(missing))

    conn_str = (
        f"DRIVER={{{driver}}};"
        f"SERVER={host},{port};"
        f"DATABASE={db_name};"
        f"UID={user};"
        f"PWD={password};"
        f"Encrypt={encrypt};"
        f"TrustServerCertificate={trust_cert};"
    )
    return pyodbc.connect(conn_str, timeout=10), driver, available


def fetch_columns(conn, view_sql):
    cursor = conn.cursor()
    cursor.execute(f"SELECT TOP 0 * FROM {view_sql}")
    return [col[0] for col in cursor.description or []]


def scalar(conn, query):
    cursor = conn.cursor()
    row = cursor.execute(query).fetchone()
    return row[0] if row else None


def run_check():
    report = {
        "status": "technical_test_pending",
        "checked_at": utc_now(),
        "source_client_code": None,
        "db_type": None,
        "host": None,
        "port": None,
        "database": None,
        "schema": None,
        "view": None,
        "view_sql": None,
        "required_columns": sorted(REQUIRED_COLUMNS),
        "recommended_columns": sorted(RECOMMENDED_COLUMNS),
        "required_columns_ok": False,
        "recommended_columns_ok": False,
        "missing_required_columns": [],
        "missing_recommended_columns": [],
        "warnings": [],
        "errors": [],
    }

    conn = None
    try:
        load_envs()

        view_sql = source_view_name()
        source_client_code = os.getenv("SOURCE_CLIENT_CODE") or os.getenv("SOURCE_DB_CLIENT_CODE") or "greenhouse"

        report.update({
            "source_client_code": source_client_code,
            "db_type": os.getenv("SOURCE_DB_TYPE", "sqlserver"),
            "host": os.getenv("SOURCE_DB_HOST"),
            "port": os.getenv("SOURCE_DB_PORT", "1433"),
            "database": os.getenv("SOURCE_DB_NAME"),
            "schema": os.getenv("SOURCE_DB_SCHEMA", "dbo"),
            "view": os.getenv("SOURCE_DB_VIEW", "GREENBRAIN_VIEW_SALES_RAW"),
            "view_sql": view_sql,
        })

        conn, driver, available_drivers = sqlserver_connection()
        report["odbc_driver"] = driver
        report["available_odbc_drivers"] = available_drivers
        report["connection_ok"] = True

        columns = fetch_columns(conn, view_sql)
        columns_lower = {c.lower(): c for c in columns}
        report["columns"] = columns

        missing_required = sorted([c for c in REQUIRED_COLUMNS if c not in columns_lower])
        missing_recommended = sorted([c for c in RECOMMENDED_COLUMNS if c not in columns_lower])

        report["missing_required_columns"] = missing_required
        report["missing_recommended_columns"] = missing_recommended
        report["required_columns_ok"] = not missing_required
        report["recommended_columns_ok"] = not missing_recommended

        if missing_recommended:
            report["warnings"].append("missing_recommended_columns")

        if not missing_required:
            report["row_count"] = int(scalar(conn, f"SELECT COUNT_BIG(*) FROM {view_sql}") or 0)
            report["max_data_movimento"] = scalar(conn, f"SELECT MAX(data_movimento) FROM {view_sql}")
            report["status"] = "technical_test_ok"
        else:
            report["status"] = "technical_test_failed"
            report["errors"].append("missing_required_columns")

    except Exception as exc:
        report["status"] = "technical_test_failed"
        report["connection_ok"] = False
        report["errors"].append(str(exc))
        report["traceback"] = traceback.format_exc()
    finally:
        if conn is not None:
            conn.close()

    latest = write_report(report)
    print(json.dumps(report, ensure_ascii=False, indent=2, default=str))
    print(f"SOURCE_DB_TECHNICAL_CHECK_REPORT={latest}")
    if report["status"] != "technical_test_ok":
        raise SystemExit(2)


if __name__ == "__main__":
    run_check()
