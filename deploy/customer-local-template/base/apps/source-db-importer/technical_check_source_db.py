import json
import os
import traceback
from datetime import datetime, timezone
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


SOURCE_COLUMN_CANDIDATES = {
    "progressivo": ["progressivo", "Progressivo", "PROGRESSIVO"],
    "codart": ["codart", "CodArt", "CODART"],
    "descrizione": ["descrizione", "DESCRIZIONE"],
    "quantita": ["quantita", "QUANTITA", "qta", "QTA"],
    "imponibile_netto": ["imponibile_netto", "IMPONIBILE_NETTO", "IMPONIBILENETTO"],
    "data_movimento": ["data_movimento", "DATA_MOVIMENTO", "DATA"],
    "tipo": ["tipo", "TIPO"],
    "fascia": ["fascia", "FASCIA"],
    "categoria": ["categoria", "CATEGORIA"],
    "disattivato": ["disattivato", "DISATTIVATO"],
    "movim_cassa": ["movim_cassa", "MOVIM_CASSA"],
}


def normalize_column_key(value):
    return (
        str(value or "")
        .strip()
        .strip("[]")
        .replace(" ", "")
        .replace("-", "")
        .replace("_", "")
        .lower()
    )


def resolve_column_mapping(columns):
    lookup = {normalize_column_key(col): col for col in columns}
    resolved = {}
    missing_required = []
    missing_recommended = []

    for logical in sorted(REQUIRED_COLUMNS):
        found = None
        for candidate in SOURCE_COLUMN_CANDIDATES.get(logical, [logical]):
            found = lookup.get(normalize_column_key(candidate))
            if found:
                break
        if found:
            resolved[logical] = found
        else:
            missing_required.append(logical)

    for logical in sorted(RECOMMENDED_COLUMNS):
        found = None
        for candidate in SOURCE_COLUMN_CANDIDATES.get(logical, [logical]):
            found = lookup.get(normalize_column_key(candidate))
            if found:
                break
        if found:
            resolved[logical] = found
        else:
            missing_recommended.append(logical)

    return resolved, sorted(missing_required), sorted(missing_recommended)


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


def classify_source_db_failure(error_message):
    """Return a stable, customer-facing failure classification.

    The checker keeps status technical_test_failed / technical_test_ok for backward
    compatibility. These extra report fields can be rendered by cloud/frontend
    without a DB migration.
    """
    msg = str(error_message or "")
    low = msg.lower()

    if "missing_source_db_env:" in low:
        return {
            "failure_code": "missing_source_db_env",
            "failure_message": "Configurazione Source DB locale non trovata.",
            "action_required": "Genera o copia il file overlay/env/source-db.env con i dati del gestionale prima di eseguire il test tecnico.",
        }

    if "missing_source_db_env_values:" in low:
        missing = msg.split(":", 1)[1] if ":" in msg else ""
        return {
            "failure_code": "missing_source_db_env_values",
            "failure_message": f"Configurazione Source DB incompleta: {missing}".strip(),
            "action_required": "Completa host, database, utente e password SQL Server nel file source-db.env.",
        }

    if "no_compatible_sqlserver_odbc_driver" in low:
        return {
            "failure_code": "missing_odbc_driver",
            "failure_message": "Driver ODBC SQL Server non disponibile nel runtime locale.",
            "action_required": "Verificare l'immagine source-db-importer e la presenza di ODBC Driver 18/17 per SQL Server.",
        }

    if "missing_required_columns" in low:
        missing = msg.split(":", 1)[1] if ":" in msg else ""
        return {
            "failure_code": "missing_required_columns",
            "failure_message": f"La vista SQL non espone tutte le colonne obbligatorie: {missing}".strip(),
            "action_required": "Chiedere al gestore DB di creare/correggere la vista GREENBRAIN_VIEW_SALES_RAW con le colonne standard richieste.",
        }

    if "login failed" in low or "authentication" in low or "28000" in low:
        return {
            "failure_code": "sql_auth_failed",
            "failure_message": "Autenticazione SQL Server non riuscita.",
            "action_required": "Verificare utente read-only e password SQL Server nel file source-db.env.",
        }

    if (
        "timeout" in low
        or "timed out" in low
        or "08001" in low
        or "could not open a connection" in low
        or "network-related" in low
        or "server is not found" in low
    ):
        return {
            "failure_code": "sql_network_unreachable",
            "failure_message": "SQL Server non raggiungibile dal runtime locale.",
            "action_required": "Verificare host, porta, rete locale/VPN, firewall e abilitazione TCP/IP di SQL Server.",
        }

    if (
        "invalid object name" in low
        or "object not found" in low
        or "42s02" in low
        or "does not exist" in low
    ):
        return {
            "failure_code": "source_view_not_found",
            "failure_message": "Vista Source DB non trovata nel database indicato.",
            "action_required": "Verificare schema e nome vista; lo standard consigliato è dbo.GREENBRAIN_VIEW_SALES_RAW.",
        }

    if "permission" in low or "select permission" in low or "42000" in low:
        return {
            "failure_code": "sql_permission_denied",
            "failure_message": "L'utente SQL non ha i permessi necessari sulla vista.",
            "action_required": "Concedere SELECT all'utente read-only sulla vista vendite configurata.",
        }

    if "data_movimento" in low:
        return {
            "failure_code": "data_movimento_query_failed",
            "failure_message": "Controllo sulla colonna data_movimento non riuscito.",
            "action_required": "Verificare che la vista esponga data_movimento come data valida e interrogabile.",
        }

    return {
        "failure_code": "unknown_source_db_error",
        "failure_message": msg[:500] if msg else "Errore tecnico Source DB non classificato.",
        "action_required": "Controllare il report tecnico completo e verificare configurazione SQL Server, vista, permessi e rete.",
    }


def apply_source_db_failure_classification(report):
    """Classify non-exception technical failures already stored in report['errors']."""
    if report.get("status") != "technical_test_failed":
        return report

    if report.get("failure_code"):
        return report

    errors = report.get("errors") or []
    if isinstance(errors, list) and errors:
        first = str(errors[0])
    else:
        first = str(report.get("error") or "")

    report.update(classify_source_db_failure(first))
    return report


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
        source_client_code = (
            os.getenv("SOURCE_DB_CLIENT_CODE")
            or os.getenv("SOURCE_CLIENT_CODE")
            or os.getenv("TENANT_CODE")
            or os.getenv("CUSTOMER_TENANT_CODE")
            or "greenbrain"
        )

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
        report["columns"] = columns

        effective_mapping, missing_required, missing_recommended = resolve_column_mapping(columns)

        report["effective_column_mapping"] = effective_mapping
        report["missing_required_columns"] = missing_required
        report["missing_recommended_columns"] = missing_recommended
        report["required_columns_ok"] = not missing_required
        report["recommended_columns_ok"] = not missing_recommended

        if missing_recommended:
            report["warnings"].append("missing_recommended_columns")

        if not missing_required:
            data_movimento_col = quote_sqlserver_identifier(effective_mapping["data_movimento"])
            report["row_count"] = int(scalar(conn, f"SELECT COUNT_BIG(*) FROM {view_sql}") or 0)
            report["max_data_movimento"] = scalar(conn, f"SELECT MAX({data_movimento_col}) FROM {view_sql}")
            report["failure_code"] = None
            report["failure_message"] = None
            report["action_required"] = None
            report["status"] = "technical_test_ok"
        else:
            report["status"] = "technical_test_failed"
            report["errors"].append("missing_required_columns:" + ",".join(missing_required))
            apply_source_db_failure_classification(report)

    except Exception as exc:
        report["status"] = "technical_test_failed"
        report["connection_ok"] = False
        report["errors"].append(str(exc))
        report.update(classify_source_db_failure(str(exc)))
        report["traceback"] = traceback.format_exc()
    finally:
        if conn is not None:
            conn.close()

    apply_source_db_failure_classification(report)
    latest = write_report(report)
    print(json.dumps(report, ensure_ascii=False, indent=2, default=str))
    print(f"SOURCE_DB_TECHNICAL_CHECK_REPORT={latest}")
    if report["status"] != "technical_test_ok":
        raise SystemExit(2)


if __name__ == "__main__":
    run_check()
