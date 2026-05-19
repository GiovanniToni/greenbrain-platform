#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV="$ROOT/overlay/env/customer-local.env"

[ -f "$ENV" ] || { echo "ERROR: missing $ENV"; exit 1; }

set -a
source "$ENV"
set +a

EMAIL="${LOCAL_CUSTOMER_EMAIL:-}"
PASSWORD="${LOCAL_CUSTOMER_TEMP_PASSWORD:-}"
FULL_NAME="${LOCAL_CUSTOMER_FULL_NAME:-}"
TENANT="${LOCAL_CUSTOMER_TENANT_CODE:-${TENANT_CODE:-}}"
HOME_HOST="${LOCAL_CUSTOMER_HOME_HOST:-${TENANT}.greenbrain.it}"
HOME_PATH="${LOCAL_CUSTOMER_HOME_PATH:-/dashboard}"
USER_ROLE="${LOCAL_CUSTOMER_USER_ROLE:-customer_admin}"

if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ] || [ -z "$TENANT" ]; then
  echo "LOCAL_USER_PROVISION_SKIPPED missing LOCAL_CUSTOMER_EMAIL/LOCAL_CUSTOMER_TEMP_PASSWORD/TENANT"
  exit 0
fi

COMPOSE_FILE="$ROOT/docker-compose.local.yml"
if [ -f "$ROOT/docker-compose.prebuilt.yml" ]; then
  COMPOSE_FILE="$ROOT/docker-compose.prebuilt.yml"
fi

echo "== GreenBrain Local User Provisioning =="
echo "email: $EMAIL"
echo "tenant: $TENANT"
echo "home: https://$HOME_HOST$HOME_PATH"

docker compose --env-file "$ENV" -f "$COMPOSE_FILE" exec -T backend python - <<'PY'
import os
from sqlalchemy import create_engine, inspect, text
from app.core.security import hash_password

email = os.environ.get("LOCAL_CUSTOMER_EMAIL", "").strip().lower()
password = os.environ.get("LOCAL_CUSTOMER_TEMP_PASSWORD", "").strip()
full_name = os.environ.get("LOCAL_CUSTOMER_FULL_NAME", "").strip() or None
tenant = (os.environ.get("LOCAL_CUSTOMER_TENANT_CODE") or os.environ.get("TENANT_CODE") or "").strip()
home_host = (os.environ.get("LOCAL_CUSTOMER_HOME_HOST") or (tenant + ".greenbrain.it")).strip()
home_path = (os.environ.get("LOCAL_CUSTOMER_HOME_PATH") or "/dashboard").strip()
user_role = (os.environ.get("LOCAL_CUSTOMER_USER_ROLE") or "customer_admin").strip()
database_url = os.environ.get("DATABASE_URL", "").strip()

if not email or not password or not tenant or not database_url:
    raise SystemExit("LOCAL_USER_PROVISION_FAILED missing env")

engine = create_engine(database_url, future=True, pool_pre_ping=True)

with engine.begin() as conn:
    insp = inspect(conn)
    cols = {c["name"] for c in insp.get_columns("greenbrain_users", schema="public")}

    payload = {
        "email": email,
        "hashed_password": hash_password(password),
        "full_name": full_name,
        "is_active": True,
        "is_admin": False,
    }

    optional = {
        "tenant_code": tenant,
        "home_host": home_host,
        "home_path": home_path,
        "user_role": user_role,
        "can_access_app": True,
    }

    for key, value in optional.items():
        if key in cols:
            payload[key] = value

    existing = conn.execute(
        text("select email from public.greenbrain_users where email = :email limit 1"),
        {"email": email},
    ).mappings().first()

    if existing:
        set_parts = [f"{key} = :{key}" for key in payload.keys() if key != "email"]
        conn.execute(
            text(f"update public.greenbrain_users set {', '.join(set_parts)} where email = :email"),
            payload,
        )
    else:
        insert_cols = ", ".join(payload.keys())
        insert_vals = ", ".join(f":{key}" for key in payload.keys())
        conn.execute(
            text(f"insert into public.greenbrain_users ({insert_cols}) values ({insert_vals})"),
            payload,
        )

    row = conn.execute(
        text("""
            select email, full_name, is_active, is_admin,
                   tenant_code, home_host, home_path, user_role, can_access_app
            from public.greenbrain_users
            where email = :email
            limit 1
        """),
        {"email": email},
    ).mappings().first()

print("LOCAL_USER_PROVISION_OK")
print(dict(row))
PY
