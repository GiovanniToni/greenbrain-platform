#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${APP_ENV:-dev}"
BASE="/opt/greenbrain-platform/infra/env"

set -a
[ -f "$BASE/base.env" ] && source "$BASE/base.env"
[ -f "$BASE/$ENV_NAME.env" ] && source "$BASE/$ENV_NAME.env"
set +a

PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-postgres}"
PG_SSLMODE="${PG_SSLMODE:-require}"

if [ -z "${DATABASE_URL:-}" ] && \
   [ -n "${PG_HOST:-}" ] && \
   [ -n "${PG_USER:-}" ] && \
   [ -n "${PG_PASSWORD:-}" ]; then
  export DATABASE_URL="postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:${PG_PORT}/${PG_DB}?sslmode=${PG_SSLMODE}"
fi

case "${PG_HOST:-}" in
  ""|"..."|*"/"*|*" "*)
    echo "[ENV][ERROR] invalid PG_HOST='${PG_HOST:-}'" >&2
    return 1 2>/dev/null || exit 1
    ;;
esac

case "${DATABASE_URL:-}" in
  *"@...:"*|*"//...:"*|*"postgres:...@"*)
    echo "[ENV][ERROR] DATABASE_URL still contains placeholder values" >&2
    return 1 2>/dev/null || exit 1
    ;;
esac

echo "[ENV] loaded base.env + ${ENV_NAME}.env"
[ -n "${DATABASE_URL:-}" ] && echo "[ENV] DATABASE_URL ready"
