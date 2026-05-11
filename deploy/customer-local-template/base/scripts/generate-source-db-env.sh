#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/overlay/env/source-db.env"

mkdir -p "$ROOT/overlay/env"

ask() {
  local label="$1"
  local default="${2:-}"
  local value

  if [ -n "$default" ]; then
    read -r -p "$label [$default]: " value
    echo "${value:-$default}"
  else
    read -r -p "$label: " value
    echo "$value"
  fi
}

ask_secret() {
  local label="$1"
  local value
  read -r -s -p "$label: " value
  echo
  echo "$value"
}

echo "== GreenBrain Source DB Wizard =="
echo

SOURCE_DB_ENABLED="$(ask "Enable Source DB import? yes/no" "yes")"
SOURCE_DB_TYPE="$(ask "Source DB type" "sqlserver")"
SOURCE_CLIENT_CODE="$(ask "Source client code" "greenhouse")"
SOURCE_DB_HOST="$(ask "SQL Server host/IP" "192.168.1.10")"
SOURCE_DB_PORT="$(ask "SQL Server port" "1433")"
SOURCE_DB_NAME="$(ask "SQL Server database name" "CHANGE_ME_DB")"
SOURCE_DB_USER="$(ask "SQL Server readonly user" "CHANGE_ME_USER")"
SOURCE_DB_PASSWORD="$(ask_secret "SQL Server password")"
SOURCE_DB_SCHEMA="$(ask "SQL Server schema" "dbo")"
SOURCE_DB_VIEW="$(ask "Sales view name" "GREENHOUSE_VIEW_STAT")"
SOURCE_DB_ENCRYPT="$(ask "Encrypt connection? yes/no" "no")"
SOURCE_DB_TRUST_CERT="$(ask "Trust server certificate? yes/no" "yes")"

cat > "$OUT" <<EOF
# GreenBrain Source DB config
SOURCE_DB_ENABLED=$SOURCE_DB_ENABLED
SOURCE_DB_TYPE=$SOURCE_DB_TYPE
SOURCE_CLIENT_CODE=$SOURCE_CLIENT_CODE

SOURCE_DB_HOST=$SOURCE_DB_HOST
SOURCE_DB_PORT=$SOURCE_DB_PORT
SOURCE_DB_NAME=$SOURCE_DB_NAME
SOURCE_DB_USER=$SOURCE_DB_USER
SOURCE_DB_PASSWORD=$SOURCE_DB_PASSWORD
SOURCE_DB_SCHEMA=$SOURCE_DB_SCHEMA
SOURCE_DB_VIEW=$SOURCE_DB_VIEW

SOURCE_DB_ENCRYPT=$SOURCE_DB_ENCRYPT
SOURCE_DB_TRUST_CERT=$SOURCE_DB_TRUST_CERT
EOF

chmod 600 "$OUT"

echo
echo "Source DB env generated:"
echo "  $OUT"
