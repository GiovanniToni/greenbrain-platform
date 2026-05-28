#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "== GreenBrain Customer Local Installer =="

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker missing"
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: Docker Compose plugin missing or not available"
  echo "Install Docker Compose plugin, then retry."
  exit 2
fi

mkdir -p "$ROOT/overlay/env" "$ROOT/overlay/provisioning"

if [ ! -f "$ROOT/overlay/env/customer-local.env" ]; then
  if [ -x "$ROOT/base/scripts/wizard/generate-customer-env.sh" ]; then
    bash "$ROOT/base/scripts/wizard/generate-customer-env.sh"
  elif [ -f "$ROOT/env/customer-local.env.example" ]; then
    cp "$ROOT/env/customer-local.env.example" "$ROOT/overlay/env/customer-local.env"
  else
    echo "ERROR: missing customer env generator/example"
    exit 3
  fi
fi

if [ ! -f "$ROOT/overlay/provisioning/local-runtime.env" ]; then
  bash "$ROOT/base/scripts/wizard/generate-runtime-env.sh"
fi

chmod +x "$ROOT"/base/scripts/*.sh

"$ROOT/base/scripts/preflight-local-install.sh"

"$ROOT/base/scripts/provision-local.sh"

export GREENBRAIN_IMAGE_TAG="${GREENBRAIN_IMAGE_TAG:-$(cat "$ROOT/VERSION" 2>/dev/null || echo latest)}"
echo "Docker image tag: $GREENBRAIN_IMAGE_TAG"


preserve_existing_local_secrets() {
  OLD_ENV="$ROOT/overlay/env/customer-local.env"
  NEW_ENV="$ROOT/overlay/env/customer-local.env"

  # If the env already exists, preserve DB/JWT secrets so update mode does not break Postgres volumes.
  if [ -f "$OLD_ENV" ]; then
    for key in POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD DATABASE_URL JWT_SECRET; do
      old_line="$(grep -E "^${key}=" "$OLD_ENV" | tail -1 || true)"
      if [ -n "$old_line" ]; then
        if grep -qE "^${key}=" "$NEW_ENV"; then
          tmp_file="${NEW_ENV}.tmp"
          awk -v k="$key" -v line="$old_line" '
            BEGIN { done=0 }
            $0 ~ "^" k "=" { print line; done=1; next }
            { print }
            END { if (!done) print line }
          ' "$NEW_ENV" > "$tmp_file"
          mv "$tmp_file" "$NEW_ENV"
        else
          printf "%s\n" "$old_line" >> "$NEW_ENV"
        fi
      fi
    done
    echo "Existing local DB/JWT secrets preserved for update mode"
  fi
}

fresh_reset_existing_stack() {
  echo "Fresh reset requested: removing existing GreenBrain local stack and data volume"
  if [ -f "$ROOT/docker-compose.prebuilt.yml" ]; then
    compose_safe -f "$ROOT/docker-compose.prebuilt.yml" --env-file "$ROOT/overlay/env/customer-local.env" down -v --remove-orphans || true
  fi
  if [ -f "$ROOT/docker-compose.local.yml" ]; then
    compose_safe -f "$ROOT/docker-compose.local.yml" --env-file "$ROOT/overlay/env/customer-local.env" down -v --remove-orphans || true
  fi
  docker rm -f greenbrain_local_backend greenbrain_local_frontend greenbrain_local_postgres greenbrain_local_ml_worker gb_customer_scheduler 2>/dev/null || true
  docker volume ls --format '{{.Name}}' | grep -Ei 'greenbrain|customer-local|customer-local-template' | while read -r v; do
    docker volume rm "$v" || true
  done
}

handle_existing_installation_mode() {
  MODE="${GREENBRAIN_INSTALL_MODE:-update}"

  if [ "${GREENBRAIN_FORCE_FRESH_INSTALL:-0}" = "1" ]; then
    MODE="fresh-reset"
  fi

  if docker ps -a --format '{{.Names}}' | grep -Eq '^(greenbrain_local_backend|greenbrain_local_postgres|greenbrain_local_frontend)$'; then
    echo "Existing GreenBrain local installation detected"
    echo "Install mode: $MODE"

    if [ "$MODE" = "fresh-reset" ]; then
      fresh_reset_existing_stack
    else
      preserve_existing_local_secrets
    fi
  fi
}



USE_PREBUILT="${GREENBRAIN_USE_PREBUILT_IMAGES:-1}"

compose_safe() {
  env \
    -u POSTGRES_DB \
    -u POSTGRES_USER \
    -u POSTGRES_PASSWORD \
    -u POSTGRES_HOST \
    -u POSTGRES_PORT \
    -u POSTGRES_SSLMODE \
    -u DATABASE_URL \
    -u TENANT_CODE \
    -u TENANT_NAME \
    -u TENANT_HOST \
    -u LOCAL_CUSTOMER_EMAIL \
    -u LOCAL_CUSTOMER_FULL_NAME \
    -u LOCAL_CUSTOMER_TEMP_PASSWORD \
    -u LOCAL_CUSTOMER_PASSWORD_HASH \
    -u LOCAL_CUSTOMER_PASSWORD_MODE \
    -u LOCAL_CUSTOMER_TENANT_CODE \
    -u LOCAL_CUSTOMER_HOME_HOST \
    -u LOCAL_CUSTOMER_HOME_PATH \
    docker compose "$@"
}



handle_existing_installation_mode

if [ "$USE_PREBUILT" = "1" ]; then
  echo "Using prebuilt Docker images"
  if ! compose_safe \
    -f "$ROOT/docker-compose.prebuilt.yml" \
    --env-file "$ROOT/overlay/env/customer-local.env" \
    up -d; then
    echo
    echo "WARN: prebuilt Docker image startup failed"
    echo "WARN: falling back to local Docker build"
    compose_safe \
      -f "$ROOT/docker-compose.local.yml" \
      --env-file "$ROOT/overlay/env/customer-local.env" \
      up -d --build
  fi
else
  echo "Using local Docker build"
  compose_safe \
    -f "$ROOT/docker-compose.local.yml" \
    --env-file "$ROOT/overlay/env/customer-local.env" \
    up -d --build
fi

echo
echo "== WAIT BACKEND HEALTH =="
set -a
source "$ROOT/overlay/env/customer-local.env"
set +a

OK=0
for i in $(seq 1 45); do
  if curl -fsS "http://localhost:${LOCAL_BACKEND_PORT:-8008}/health" >/dev/null 2>&1; then
    echo "Backend healthy"
    OK=1
    break
  fi
  sleep 2
done

if [ "$OK" -ne 1 ]; then
  echo "ERROR: backend not healthy after install"
  if [ "${USE_PREBUILT:-1}" = "1" ] && [ -f "$ROOT/docker-compose.prebuilt.yml" ]; then
    compose_safe -f "$ROOT/docker-compose.prebuilt.yml" --env-file "$ROOT/overlay/env/customer-local.env" ps || true
  fi
  compose_safe -f "$ROOT/docker-compose.local.yml" --env-file "$ROOT/overlay/env/customer-local.env" ps || true
  exit 20
fi

verify_local_db_credentials() {
  echo
  echo "== VERIFY LOCAL DB CREDENTIALS =="

  set -a
  source "$ROOT/overlay/env/customer-local.env"
  set +a

  if ! docker exec \
    -e AUTH_DB_HOST=postgres \
    -e AUTH_DB_PORT=5432 \
    -e AUTH_DB_NAME="$POSTGRES_DB" \
    -e AUTH_DB_USER="$POSTGRES_USER" \
    -e AUTH_DB_PASSWORD="$POSTGRES_PASSWORD" \
    greenbrain_local_backend python - <<'PY_DB_CHECK'
import os
import sys
import psycopg

host = os.environ.get("AUTH_DB_HOST", "postgres")
port = int(os.environ.get("AUTH_DB_PORT", "5432"))
dbname = os.environ.get("AUTH_DB_NAME", "")
user = os.environ.get("AUTH_DB_USER", "")
password = os.environ.get("AUTH_DB_PASSWORD", "")

try:
    with psycopg.connect(
        host=host,
        port=port,
        dbname=dbname,
        user=user,
        password=password,
        connect_timeout=5,
    ) as conn:
        with conn.cursor() as cur:
            cur.execute("select current_user, current_database()")
            row = cur.fetchone()
            print(f"LOCAL_DB_CREDENTIALS_OK user={row[0]} db={row[1]}")
except Exception as exc:
    print(f"LOCAL_DB_CREDENTIALS_FAILED: {type(exc).__name__}: {exc}", file=sys.stderr)
    sys.exit(31)
PY_DB_CHECK
  then
    echo
    echo "ERROR: il database locale esiste ma le credenziali non sono compatibili con questo bundle."
    echo
    echo "Probabile causa:"
    echo "  - è presente una vecchia installazione GreenBrain locale;"
    echo "  - il volume Postgres è già stato inizializzato con credenziali diverse;"
    echo "  - Postgres non aggiorna POSTGRES_PASSWORD su un volume già esistente."
    echo
    echo "Soluzione per reinstallazione pulita:"
    echo "  GREENBRAIN_FORCE_FRESH_INSTALL=1 GREENBRAIN_CONFIGURE_SOURCE_DB=no bash install.sh"
    echo
    echo "Oppure:"
    echo "  GREENBRAIN_INSTALL_MODE=fresh-reset GREENBRAIN_CONFIGURE_SOURCE_DB=no bash install.sh"
    echo
    exit 31
  fi
}

verify_local_db_credentials

"$ROOT/base/scripts/provision-local-user.sh"

"$ROOT/base/scripts/doctor-local.sh"

echo
echo
CONFIG_SOURCE_DB="${GREENBRAIN_CONFIGURE_SOURCE_DB:-}"
if [ -z "$CONFIG_SOURCE_DB" ]; then
  read -r -p "Configure Source DB now? yes/no [no]: " CONFIG_SOURCE_DB || CONFIG_SOURCE_DB="no"
fi
CONFIG_SOURCE_DB="${CONFIG_SOURCE_DB:-no}"

if [ "$CONFIG_SOURCE_DB" = "yes" ] || [ "$CONFIG_SOURCE_DB" = "y" ]; then
  bash "$ROOT/base/scripts/generate-source-db-env.sh"
else
  echo "Source DB configuration skipped. You can run later:"
  echo "  bash base/scripts/generate-source-db-env.sh"
fi

echo
echo "== INSTALL SUMMARY =="
echo "VERSION: $(cat "$ROOT/VERSION" 2>/dev/null || echo unknown)"
echo "Customer env: $ROOT/overlay/env/customer-local.env"
echo "Runtime env: $ROOT/overlay/provisioning/local-runtime.env"
if [ -f "$ROOT/overlay/env/source-db.env" ]; then
  echo "Source DB: configured"
else
  echo "Source DB: not configured"
fi
echo "Backend URL: http://localhost:${LOCAL_BACKEND_PORT:-8008}/health"
echo "Frontend URL: http://localhost:${LOCAL_FRONTEND_PORT:-8088}"
echo
echo "INSTALL COMPLETED"
