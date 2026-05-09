#!/usr/bin/env bash
set -euo pipefail

GB_LOCAL_ROOT="${GB_LOCAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
GB_LOG_DIR="${GB_LOG_DIR:-$GB_LOCAL_ROOT/overlay/logs}"
GB_RUNTIME_ENV="$GB_LOCAL_ROOT/overlay/provisioning/local-runtime.env"
GB_CUSTOMER_ENV="$GB_LOCAL_ROOT/overlay/env/customer-local.env"

mkdir -p "$GB_LOG_DIR"

gb_load_env() {
  [ -f "$GB_CUSTOMER_ENV" ] || { echo "ERROR missing $GB_CUSTOMER_ENV"; exit 1; }
  set -a
  source "$GB_CUSTOMER_ENV"
  [ -f "$GB_RUNTIME_ENV" ] && source "$GB_RUNTIME_ENV"
  set +a

  export PGHOST="${PGHOST:-${POSTGRES_HOST:-postgres}}"
  export PGPORT="${PGPORT:-${POSTGRES_PORT:-5432}}"
  export PGDATABASE="${PGDATABASE:-${POSTGRES_DB:-greenbrain}}"
  export PGUSER="${PGUSER:-${POSTGRES_USER:-greenbrain}}"
  export PGPASSWORD="${PGPASSWORD:-${POSTGRES_PASSWORD:-greenbrain}}"

  export PG_HOST="${PG_HOST:-$PGHOST}"
  export PG_PORT="${PG_PORT:-$PGPORT}"
  export PG_DB="${PG_DB:-$PGDATABASE}"
  export PG_USER="${PG_USER:-$PGUSER}"
  export PG_PASSWORD="${PG_PASSWORD:-$PGPASSWORD}"
  export PG_SSLMODE="${PG_SSLMODE:-${POSTGRES_SSLMODE:-disable}}"

  export DATABASE_URL="${DATABASE_URL:-postgresql://${PGUSER}:${PGPASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}}"

  export BACKEND_HEALTH_URL="${BACKEND_HEALTH_URL:-http://backend:8000/health}"
  export FRONTEND_HEALTH_URL="${FRONTEND_HEALTH_URL:-http://frontend:80}"
}

gb_psql() {
  gb_load_env
  psql "$DATABASE_URL" "$@"
}

gb_log() {
  echo "$(date -Iseconds) $*"
}
