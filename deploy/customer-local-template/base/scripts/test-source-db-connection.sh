#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV="$ROOT/overlay/env/source-db.env"

fail(){ echo "ERROR: $1" >&2; exit 1; }

echo "== GreenBrain Source DB Connection Test =="

[ -f "$ENV" ] || fail "missing source-db.env"

set -a
source "$ENV"
set +a

command -v timeout >/dev/null 2>&1 || fail "timeout command missing"

timeout 5 bash -c "</dev/tcp/${SOURCE_DB_HOST}/${SOURCE_DB_PORT}" \
  && echo "SOURCE_DB_TCP_OK" \
  || fail "cannot reach ${SOURCE_DB_HOST}:${SOURCE_DB_PORT}"
