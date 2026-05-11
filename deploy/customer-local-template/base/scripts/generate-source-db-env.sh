#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

OUT="$ROOT/overlay/env/source-db.env"

echo "== GreenBrain Source DB Wizard =="

read -rp "DB host: " DB_HOST
read -rp "DB port [1433]: " DB_PORT
DB_PORT="${DB_PORT:-1433}"

read -rp "DB name: " DB_NAME
read -rp "DB user: " DB_USER

read -rsp "DB password: " DB_PASSWORD
echo

read -rp "DB schema [dbo]: " DB_SCHEMA
DB_SCHEMA="${DB_SCHEMA:-dbo}"

cat > "$OUT" <<EOF
SOURCE_DB_TYPE=sqlserver

SOURCE_DB_HOST=${DB_HOST}
SOURCE_DB_PORT=${DB_PORT}

SOURCE_DB_NAME=${DB_NAME}
SOURCE_DB_USER=${DB_USER}
SOURCE_DB_PASSWORD=${DB_PASSWORD}

SOURCE_DB_SCHEMA=${DB_SCHEMA}

SOURCE_DB_ENCRYPT=false
SOURCE_DB_TRUST_CERT=true
EOF

echo
echo "Source DB env generated:"
echo "  $OUT"
