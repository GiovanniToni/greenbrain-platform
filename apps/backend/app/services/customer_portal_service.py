from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Any, Dict

from app.repositories.customer_portal_repository import (
    get_customer_by_portal_email,
    get_runtime_connection_by_tenant_code,
    update_customer_portal_fields,
)
from app.repositories.customer_source_db_repository import (
    get_source_db_integration,
    mask_source_db_integration,
    save_source_db_integration,
    update_customer_db_integration_status,
)
from app.core.secret_crypto import encrypt_secret
from app.services.customer_billing_service import (
    cancel_subscription_at_period_end_for_portal_email,
)
from app.services.customer_delivery_service import get_latest_available_release_version
import re

_SLOT_STATES_ALREADY_BOOKED = {
    "slot_requested",
    "slot_confirmed",
    "setup_in_progress",
    "data_validation_pending",
    "data_validated",
}


def derive_customer_installation_state(profile: Dict[str, Any]) -> Dict[str, Any]:
    runtime_status = (profile.get("runtime_connection_status") or "").strip().lower()
    installation_id = profile.get("latest_installation_id")
    heartbeat = profile.get("last_runtime_heartbeat_at")
    downloaded = bool(profile.get("last_downloaded_at"))

    platform_ready = bool(runtime_status == "healthy" and installation_id and heartbeat)

    if platform_ready:
        status = "healthy"
        label = "Piattaforma attiva"
        next_action = "open_platform"
    elif installation_id:
        status = "registered"
        label = "Runtime registrato, in attesa stato healthy"
        next_action = "check_runtime"
    elif downloaded:
        status = "downloaded"
        label = "Bundle scaricato, installazione non ancora collegata"
        next_action = "complete_installation"
    else:
        status = "not_started"
        label = "Installazione non ancora iniziata"
        next_action = "download_bundle"

    return {
        "platform_ready": platform_ready,
        "installation_status": status,
        "installation_status_label": label,
        "installation_next_action": next_action,
    }


def build_customer_portal_profile(user_email: str) -> Dict[str, Any]:
    row = get_customer_by_portal_email(user_email)
    if not row:
        raise RuntimeError(f"customer_portal_profile_not_found_for_email: {user_email}")

    delivery = row.get("delivery") or {}
    latest_available_release_version = get_latest_available_release_version()

    tenant_code = (row.get("tenant_code") or "").strip()
    runtime = get_runtime_connection_by_tenant_code(tenant_code) if tenant_code else None
    runtime = runtime or {}

    profile = {
        "customer_id": row.get("customer_id"),
        "tenant_code": row.get("tenant_code"),
        "company_name": row.get("company_name"),
        "vat_number": row.get("vat_number"),
        "contact_name": row.get("contact_name"),
        "contact_email": row.get("contact_email"),
        "contact_phone": row.get("contact_phone"),
        "address_line": row.get("address_line"),
        "city": row.get("city"),
        "country": row.get("country"),
        "billing_email": row.get("billing_email"),
        "portal_user_email": row.get("portal_user_email"),
        "signup_source": row.get("signup_source"),
        "signup_completed_at": row.get("signup_completed_at"),
        "onboarding_status": row.get("onboarding_status"),
        "onboarding_step": row.get("onboarding_step"),
        "db_integration_status": row.get("db_integration_status"),
        "assigned_release_version": row.get("assigned_release_version"),
        "installed_release_version": row.get("installed_release_version"),
        "runtime_connection_status": runtime.get("runtime_health") or row.get("runtime_connection_status"),
        "latest_installation_id": runtime.get("installation_id") or row.get("latest_installation_id"),
        "last_runtime_heartbeat_at": runtime.get("last_heartbeat_at") or row.get("last_runtime_heartbeat_at"),
        "runtime_public_backend_url": runtime.get("public_backend_url"),
        "runtime_local_backend_url": runtime.get("local_backend_url"),
        "runtime_local_agent_version": runtime.get("local_agent_version"),
        "runtime_connection_mode": runtime.get("connection_mode"),
        "runtime_data_mode": runtime.get("data_mode"),
        "runtime_last_sync_status": runtime.get("last_sync_status"),
        "runtime_last_sync_at": runtime.get("last_sync_at"),
        "first_downloaded_release_version": row.get("first_downloaded_release_version"),
        "first_downloaded_at": row.get("first_downloaded_at"),
        "last_downloaded_release_version": row.get("last_downloaded_release_version"),
        "last_downloaded_at": row.get("last_downloaded_at"),
        "latest_available_release_version": latest_available_release_version,
        "subscription_status": row.get("subscription_status"),
        "subscription_plan": row.get("subscription_plan"),
        "payment_method_saved": bool(row.get("payment_method_id")),
        "payment_method_last4": row.get("payment_method_last4"),
        "payment_method_brand": row.get("payment_method_brand"),
        "setup_slot_preferred_date": str(row.get("setup_slot_preferred_date") or "") or None,
        "setup_slot_preferred_time": row.get("setup_slot_preferred_time"),
        "setup_slot_requested_at": row.get("setup_slot_requested_at"),
        "setup_slot_confirmed_at": row.get("setup_slot_confirmed_at"),
        "setup_slot_scheduled_for": row.get("setup_slot_scheduled_for"),
        "data_validated_at": row.get("data_validated_at"),
        "cancellation_requested": bool(row.get("cancellation_requested")),
        "cancellation_requested_at": row.get("cancellation_requested_at"),
        "subscription_current_period_end": row.get("subscription_current_period_end"),
        "subscription_activated_at": row.get("subscription_activated_at"),
        "subscription_cancel_at_period_end": bool(row.get("subscription_cancel_at_period_end")),
        "created_at": row.get("created_at"),
        "updated_at": row.get("updated_at"),
        "delivery": {
            "assigned_release_version": delivery.get("assigned_release_version"),
            "bundle_generated_at": delivery.get("bundle_generated_at"),
            "bundle_sent_at": delivery.get("bundle_sent_at"),
            "bundle_local_path": delivery.get("bundle_local_path"),
            "install_status": delivery.get("install_status"),
            "onboarding_status": delivery.get("onboarding_status"),
            "go_live_at": delivery.get("go_live_at"),
            "updated_at": delivery.get("updated_at"),
        },
    }
    profile.update(derive_customer_installation_state(profile))
    return profile


def cancel_customer_portal_subscription(user_email: str) -> Dict[str, Any]:
    row = get_customer_by_portal_email(user_email)
    if not row:
        raise RuntimeError(f"customer_portal_profile_not_found_for_email: {user_email}")
    return cancel_subscription_at_period_end_for_portal_email(user_email)


def book_customer_setup_slot(user_email: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    row = get_customer_by_portal_email(user_email)
    if not row:
        raise RuntimeError(f"customer_portal_profile_not_found_for_email: {user_email}")

    preferred_time = (payload.get("preferred_time") or "").strip()
    if preferred_time not in ("morning", "afternoon"):
        raise RuntimeError("invalid_preferred_time: must be 'morning' or 'afternoon'")

    preferred_date_str = (payload.get("preferred_date") or "").strip()
    try:
        preferred_date = date.fromisoformat(preferred_date_str)
    except (ValueError, TypeError):
        raise RuntimeError("invalid_preferred_date: must be ISO format YYYY-MM-DD")

    today = datetime.now(timezone.utc).date()
    if preferred_date <= today:
        raise RuntimeError("invalid_preferred_date: must be a future date")

    current_status = (row.get("onboarding_status") or "").strip()
    if current_status in _SLOT_STATES_ALREADY_BOOKED:
        raise RuntimeError("slot_already_requested")

    notes = (payload.get("notes") or "").strip() or None
    now_iso = datetime.now(timezone.utc).isoformat()

    update_customer_portal_fields(user_email, {
        "setup_slot_preferred_date": preferred_date_str,
        "setup_slot_preferred_time": preferred_time,
        "setup_slot_requested_at": now_iso,
        "setup_slot_notes": notes,
        "onboarding_status": "slot_requested",
        "onboarding_step": "slot_requested",
        "updated_at": now_iso,
    })

    return {
        "status": "slot_requested",
        "preferred_date": preferred_date_str,
        "preferred_time": preferred_time,
    }


def confirm_customer_data_ok(user_email: str) -> Dict[str, Any]:
    row = get_customer_by_portal_email(user_email)
    if not row:
        raise RuntimeError(f"customer_portal_profile_not_found_for_email: {user_email}")

    current_status = (row.get("onboarding_status") or "").strip()
    if current_status != "data_validation_pending":
        raise RuntimeError("data_not_ready_for_validation")

    if not (row.get("setup_slot_confirmed_at") or row.get("setup_slot_scheduled_for")):
        raise RuntimeError("setup_slot_not_confirmed")

    if not (row.get("payment_method_id") or "").strip():
        raise RuntimeError("payment_method_missing")

    now_iso = datetime.now(timezone.utc).isoformat()
    update_customer_portal_fields(user_email, {
        "onboarding_status": "data_validated",
        "onboarding_step": "data_validated",
        "data_validated_at": now_iso,
        "updated_at": now_iso,
    })

    return {
        "status": "data_validated",
        "data_validated_at": now_iso,
    }


_SOURCE_DB_ALLOWED_STATUSES = {
    "not_started",
    "response_saved",
    "formal_validation_failed",
    "formal_validation_ok",
    "technical_test_pending",
    "technical_test_failed",
    "technical_test_ok",
}


def _clean_optional_text(value: Any) -> str | None:
    clean = str(value or "").strip()
    return clean or None


def _clean_bool(value: Any) -> bool | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        clean = value.strip().lower()
        if clean in {"1", "true", "yes", "y", "si", "sì"}:
            return True
        if clean in {"0", "false", "no", "n"}:
            return False
    return bool(value)



SOURCE_DB_STANDARD_VIEW_NAME = "GREENBRAIN_VIEW_SALES_RAW"

SOURCE_DB_REQUIRED_COLUMNS = [
    "progressivo",
    "codart",
    "descrizione",
    "quantita",
    "imponibile_netto",
    "data_movimento",
]

SOURCE_DB_RECOMMENDED_COLUMNS = [
    "tipo",
    "fascia",
    "categoria",
    "disattivato",
    "movim_cassa",
]


def build_source_db_manager_request(user_email: str) -> Dict[str, Any]:
    """Build the request text the customer can send to the DB/software manager."""
    row = get_customer_by_portal_email(user_email)
    if not row:
        raise RuntimeError(f"customer_portal_profile_not_found_for_email: {user_email}")

    company_name = row.get("company_name") or row.get("tenant_code") or "cliente GreenBrain"
    tenant_code = row.get("tenant_code") or ""

    subject = f"Richiesta dati tecnici per collegamento GreenBrain al gestionale - {company_name}"

    body = f"""Buongiorno,

stiamo configurando GreenBrain per leggere in sola lettura i dati di vendita dal gestionale/database SQL Server.

Per completare la configurazione servono queste informazioni:

1. Server SQL / istanza raggiungibile dal computer locale dove verrà installato GreenBrain
   Esempio: SERVERGREEN\\FLORINFO oppure 192.168.1.10

2. Porta SQL Server
   Esempio: 1433, oppure indicare se si usa istanza nominata/dinamica

3. Nome database
   Esempio: AZIEN001

4. Schema
   Esempio: dbo

5. Nome vista vendite da usare per GreenBrain
   Standard consigliato: {SOURCE_DB_STANDARD_VIEW_NAME}

6. Utente SQL Server dedicato in sola lettura
   L'utente deve poter eseguire SELECT sulla vista indicata.
   Non usare preferibilmente utenti amministrativi come sa.

7. Conferma se la connessione richiede Encrypt e TrustServerCertificate.

Vista standard consigliata:

CREATE VIEW dbo.{SOURCE_DB_STANDARD_VIEW_NAME} AS
SELECT
  Progressivo AS progressivo,
  CodArt AS codart,
  DESCRIZIONE AS descrizione,
  TIPO AS tipo,
  FASCIA AS fascia,
  CATEGORIA AS categoria,
  QUANTITA AS quantita,
  IMPONIBILENETTO AS imponibile_netto,
  DATA AS data_movimento,
  DISATTIVATO AS disattivato,
  MOVIM_CASSA AS movim_cassa
FROM dbo.GREENHOUSE_VIEW_STAT;

Colonne obbligatorie richieste da GreenBrain:
- progressivo
- codart
- descrizione
- quantita
- imponibile_netto
- data_movimento

Colonne raccomandate:
- tipo
- fascia
- categoria
- disattivato
- movim_cassa

Per favore rispondere compilando, se possibile, questo schema:

Server SQL / istanza:
Porta:
Database:
Schema:
Vista:
Utente read-only:
Encrypt:
TrustServerCertificate:
Note rete/VPN/firewall:

Grazie.
"""

    return {
        "status": "request_ready",
        "tenant_code": tenant_code,
        "company_name": company_name,
        "subject": subject,
        "body": body,
        "standard_view_name": SOURCE_DB_STANDARD_VIEW_NAME,
        "required_columns": SOURCE_DB_REQUIRED_COLUMNS,
        "recommended_columns": SOURCE_DB_RECOMMENDED_COLUMNS,
    }


def _normalize_manager_response_line_value(value: str | None) -> str | None:
    clean = str(value or "").strip().strip("`").strip()
    if not clean:
        return None
    return clean.strip(" ,;.")


def _extract_labeled_value(text: str, labels: list[str]) -> str | None:
    """Extract a labelled value from the same line only.

    Do not consume the next line when a label is empty, for example:
    "Database\nSchema:" must not parse db_name="Schema".
    """
    label_alt = "|".join(labels)
    pattern = rf"(?im)^[ \t]*(?:{label_alt})[ \t]*(?:\:|\=|\-|\u2013|\u2014)[ \t]*([^\r\n]+)[ \t]*$"
    return _extract_first_pattern(text, pattern)


def _extract_first_pattern(text: str, pattern: str) -> str | None:
    match = re.search(pattern, text, flags=re.IGNORECASE | re.MULTILINE)
    if match:
        return _normalize_manager_response_line_value(match.group(1))
    return None


# INLINE_SOURCE_DB_PARSE_FALLBACKS: accept common Italian/free-text replies
# such as "server 192.0.2.10 porta 1433 database X utente Y".
# Password values are intentionally never extracted or returned.
def _extract_inline_token_after_label(text: str, labels: list[str], token_pattern: str = r"[^\s,;]+") -> str | None:
    """Extract inline tokens without crossing line boundaries.

    This avoids parsing UI/template labels such as:
    "Database\nSchema:" as database="Schema".
    """
    label_alt = "|".join(labels)
    pattern = rf"(?i)\b(?:{label_alt})\b[ \t]*(?:\:|\=|\-|\u2013|\u2014|è|e'|is)?[ \t]*({token_pattern})"
    return _extract_first_pattern(text, pattern)


def _parse_bool_hint(value: str | None) -> bool | None:
    if value is None:
        return None
    clean = value.strip().lower()
    if clean in {"1", "true", "yes", "y", "si", "sì", "attivo", "abilitato", "obbligatorio"}:
        return True
    if clean in {"0", "false", "no", "n", "non", "disattivo", "disabilitato"}:
        return False
    return None


def parse_source_db_manager_response(user_email: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    """Parse free-text response from DB/software manager.

    Passwords are intentionally not extracted from free text.
    """
    row = get_customer_by_portal_email(user_email)
    if not row:
        raise RuntimeError(f"customer_portal_profile_not_found_for_email: {user_email}")

    text = str(payload.get("manager_response_raw_text") or "").strip()

    suggested_payload: Dict[str, Any] = {
        "db_type": "sqlserver",
        "source_client_code": row.get("tenant_code") or None,
        "db_port": 1433,
        "db_schema": "dbo",
        "db_view_name": SOURCE_DB_STANDARD_VIEW_NAME,
        "db_encrypt": True,
        "db_trust_server_certificate": True,
        "manager_response_raw_text": text,
    }

    if not text:
        return {
            "status": "parse_failed",
            "parsed": {},
            "missing": ["risposta gestore DB"],
            "warnings": [],
            "password_detected": False,
            "manager_response_raw_text": "",
            "suggested_payload": suggested_payload,
        }

    parsed: Dict[str, Any] = {}

    host = _extract_labeled_value(text, [
        r"server(?:\s+sql)?(?:\s*/\s*istanza)?",
        r"server\s*sql\s*/\s*istanza",
        r"sql\s*server",
        r"host",
        r"istanza",
    ])
    if not host:
        host = _extract_first_pattern(text, r"\b([A-Z0-9_.-]+\\[A-Z0-9_.-]+)\b")
    if not host:
        host = _extract_first_pattern(text, r"\b((?:\d{1,3}\.){3}\d{1,3})\b")
    if host:
        parsed["db_host"] = host

    port = _extract_labeled_value(text, [r"porta", r"port"])
    if not port:
        port = _extract_inline_token_after_label(text, [r"porta", r"port"], r"[0-9]{2,5}")
    if port:
        port_digits = re.sub(r"[^0-9]", "", port)
        if port_digits:
            parsed["db_port"] = int(port_digits)

    db_name = _extract_labeled_value(text, [r"database", r"nome\s+database", r"db"])
    if not db_name:
        db_name = _extract_inline_token_after_label(text, [r"database", r"nome\s+database", r"db"], r"[A-Z0-9_.-]+")
    if not db_name:
        db_name = _extract_first_pattern(text, r"\b(AZIEN[0-9A-Z_]+)\b")
    if db_name:
        parsed["db_name"] = db_name

    schema = _extract_labeled_value(text, [r"schema"])
    if not schema:
        schema = _extract_inline_token_after_label(text, [r"schema"], r"[A-Z0-9_.-]+")
    if schema:
        parsed["db_schema"] = schema

    view_name = _extract_labeled_value(text, [r"vista", r"view", r"vista\s+vendite", r"nome\s+vista"])
    if not view_name:
        view_name = _extract_inline_token_after_label(text, [r"vista", r"view", r"vista\s+vendite", r"nome\s+vista"], r"[A-Z0-9_.-]+")
    if not view_name:
        if re.search(r"\bGREENBRAIN_VIEW_SALES_RAW\b", text, flags=re.IGNORECASE):
            view_name = SOURCE_DB_STANDARD_VIEW_NAME
        elif re.search(r"\bGREENHOUSE_VIEW_STAT\b", text, flags=re.IGNORECASE):
            view_name = "GREENHOUSE_VIEW_STAT"
    if view_name:
        parsed["db_view_name"] = view_name

    username = _extract_labeled_value(text, [r"utente(?:\s+sql)?(?:\s+read-only)?", r"utente(?:\s+read-only)?", r"user", r"username", r"login", r"uid"])
    if not username:
        username = _extract_inline_token_after_label(
            text,
            [r"utente(?:\s+sql)?(?:\s+read-only)?", r"utente(?:\s+read-only)?", r"user", r"username", r"login", r"uid"],
            r"[A-Z0-9_.\\@-]+",
        )
    if username:
        # SOURCE_DB_USERNAME_LABEL_GUARD: avoid treating UI/template labels
        # such as "Utente read-only:" as the actual SQL username.
        username_clean = username.strip().lower().strip(":")
        if username_clean in {
            "read-only",
            "readonly",
            "utente",
            "utente read-only",
            "user",
            "username",
            "login",
            "uid",
            "encrypt",
            "password",
            "pwd",
            "pw",
        }:
            username = None

    if username:
        parsed["db_username"] = username

    encrypt = _extract_labeled_value(text, [r"encrypt", r"crittografia"])
    trust = _extract_labeled_value(text, [r"trustservercertificate", r"trust\s+server\s+certificate", r"trust\s+cert"])
    parsed_encrypt = _parse_bool_hint(encrypt)
    parsed_trust = _parse_bool_hint(trust)
    if parsed_encrypt is not None:
        parsed["db_encrypt"] = parsed_encrypt
    if parsed_trust is not None:
        parsed["db_trust_server_certificate"] = parsed_trust

    password_detected = bool(re.search(
        r"(?im)(^|\b)(password|pwd|pw|pass|secret|parola\s+chiave)\b\s*(\:|\=|\-|\u2013|\u2014|\s+)",
        text,
    ))

    suggested_payload.update(parsed)

    missing = []
    for key, label in {
        "db_host": "server/host gestionale",
        "db_name": "nome database",
        "db_view_name": "nome vista",
        "db_username": "utente read-only",
    }.items():
        if not suggested_payload.get(key):
            missing.append(label)

    warnings = []
    if password_detected:
        warnings.append("La risposta sembra contenere una password: per sicurezza non viene precompilata. Inseriscila solo nel campo password DB.")
    if str(suggested_payload.get("db_username") or "").strip().lower() == "sa":
        warnings.append("L'utente indicato sembra essere 'sa': usare preferibilmente un utente dedicato in sola lettura.")
    if str(suggested_payload.get("db_view_name") or "").strip().upper() == "GREENHOUSE_VIEW_STAT":
        warnings.append("Vista legacy GREENHOUSE_VIEW_STAT rilevata; preferibile creare alias standard GREENBRAIN_VIEW_SALES_RAW.")

    status = "parse_ok" if parsed else "parse_failed"
    if parsed and missing:
        status = "parse_partial"

    return {
        "status": status,
        "parsed": parsed,
        "missing": missing,
        "warnings": warnings,
        "password_detected": password_detected,
        "manager_response_raw_text": text,
        "suggested_payload": suggested_payload,
    }


def _build_source_db_formal_validation(payload: Dict[str, Any], *, password_set: bool) -> Dict[str, Any]:
    missing = []

    if not _clean_optional_text(payload.get("db_host")):
        missing.append("server/host gestionale")
    if not _clean_optional_text(payload.get("db_name")):
        missing.append("nome database")
    if not _clean_optional_text(payload.get("db_view_name")):
        missing.append("nome vista")
    if not _clean_optional_text(payload.get("db_username")):
        missing.append("utente read-only")
    if not password_set:
        missing.append("password utente read-only")

    warnings = []
    username = (_clean_optional_text(payload.get("db_username")) or "").lower()
    if username == "sa":
        warnings.append("L'utente SQL Server indicato è 'sa': usare preferibilmente un utente dedicato read-only.")

    view_name = (_clean_optional_text(payload.get("db_view_name")) or "").upper()
    if view_name == "GREENHOUSE_VIEW_STAT":
        warnings.append("Vista legacy GREENHOUSE_VIEW_STAT accettata; preferibile alias standard GREENBRAIN_VIEW_SALES_RAW.")

    if missing:
        status = "formal_validation_failed"
        title = "Validazione formale non completata"
    else:
        status = "formal_validation_ok"
        title = "Validazione formale completata"

    lines = [
        title,
        "",
        "Controlli formali:",
        f"- Server/host: {'OK' if 'server/host gestionale' not in missing else 'MANCANTE'}",
        f"- Database: {'OK' if 'nome database' not in missing else 'MANCANTE'}",
        f"- Vista: {'OK' if 'nome vista' not in missing else 'MANCANTE'}",
        f"- Utente: {'OK' if 'utente read-only' not in missing else 'MANCANTE'}",
        f"- Password: {'OK' if password_set else 'MANCANTE'}",
    ]

    if warnings:
        lines.extend(["", "Avvisi:"])
        lines.extend([f"- {w}" for w in warnings])

    if missing:
        lines.extend(["", "Dati da completare:"])
        lines.extend([f"- {m}" for m in missing])

    return {
        "status": status,
        "missing": missing,
        "warnings": warnings,
        "report": "\n".join(lines),
    }


def get_customer_source_db_state(user_email: str) -> Dict[str, Any]:
    row = get_customer_by_portal_email(user_email)
    if not row:
        raise RuntimeError(f"customer_portal_profile_not_found_for_email: {user_email}")

    integration = get_source_db_integration(row["customer_id"])
    return {
        "customer_id": row.get("customer_id"),
        "tenant_code": row.get("tenant_code"),
        "db_integration_status": row.get("db_integration_status") or "not_started",
        "source_db_integration": mask_source_db_integration(integration),
    }


def save_customer_source_db_state(user_email: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    row = get_customer_by_portal_email(user_email)
    if not row:
        raise RuntimeError(f"customer_portal_profile_not_found_for_email: {user_email}")

    customer_id = row["customer_id"]
    existing = get_source_db_integration(customer_id) or {}

    password = str(payload.get("password") or "").strip()
    password_set = bool(existing.get("db_password_set"))

    db_payload: Dict[str, Any] = {
        "db_type": _clean_optional_text(payload.get("db_type")) or "sqlserver",
        "db_host": _clean_optional_text(payload.get("db_host")),
        "db_port": int(payload.get("db_port") or 1433),
        "db_name": _clean_optional_text(payload.get("db_name")),
        "db_schema": _clean_optional_text(payload.get("db_schema")) or "dbo",
        "source_client_code": _clean_optional_text(payload.get("source_client_code")),
        "db_view_name": _clean_optional_text(payload.get("db_view_name")) or "GREENBRAIN_VIEW_SALES_RAW",
        "db_username": _clean_optional_text(payload.get("db_username")),
        "db_encrypt": _clean_bool(payload.get("db_encrypt")),
        "db_trust_server_certificate": _clean_bool(payload.get("db_trust_server_certificate")),
        "manager_contact_email": _clean_optional_text(payload.get("manager_contact_email")),
        "manager_response_raw_text": _clean_optional_text(payload.get("manager_response_raw_text")),
        "notes": _clean_optional_text(payload.get("notes")),
    }

    if password:
        db_payload["db_password_encrypted"] = encrypt_secret(password)
        db_payload["db_password_set"] = True
        password_set = True

    validation = _build_source_db_formal_validation(db_payload, password_set=password_set)
    now_iso = datetime.now(timezone.utc).isoformat()

    db_payload.update({
        "formal_validation_status": validation["status"],
        "formal_validation_report": validation["report"],
        "formal_validation_result": {
            "missing": validation["missing"],
            "warnings": validation["warnings"],
        },
        "formal_validation_at": now_iso,
        "technical_test_status": existing.get("technical_test_status") or "not_started",
    })

    saved = save_source_db_integration(customer_id, db_payload)
    update_customer_db_integration_status(customer_id, validation["status"])

    return {
        "customer_id": customer_id,
        "tenant_code": row.get("tenant_code"),
        "db_integration_status": validation["status"],
        "source_db_integration": mask_source_db_integration(saved),
    }
