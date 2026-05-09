#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR="$ROOT/overlay/source-db"
OUT_FILE="$OUT_DIR/sqlserver.env"

mkdir -p "$OUT_DIR"

read -rp "SQL Server host/IP: " SQLSERVER_HOST
read -rp "SQL Server port [1433]: " SQLSERVER_PORT
SQLSERVER_PORT="${SQLSERVER_PORT:-1433}"
read -rp "SQL Server database: " SQLSERVER_DATABASE
read -rp "SQL Server username: " SQLSERVER_USER
read -rsp "SQL Server password: " SQLSERVER_PASSWORD
echo

cat > "$OUT_FILE" <<EOF
SQLSERVER_HOST=${SQLSERVER_HOST}
SQLSERVER_PORT=${SQLSERVER_PORT}
SQLSERVER_DATABASE=${SQLSERVER_DATABASE}
SQLSERVER_USER=${SQLSERVER_USER}
SQLSERVER_PASSWORD=${SQLSERVER_PASSWORD}
SQLSERVER_TRUST_SERVER_CERTIFICATE=true
EOF

chmod 600 "$OUT_FILE"

echo
echo "SQL Server config written:"
echo "  $OUT_FILE"
echo
echo "Testing TCP connectivity..."

if timeout 5 bash -lc "cat < /dev/null > /dev/tcp/${SQLSERVER_HOST}/${SQLSERVER_PORT}" 2>/dev/null; then
  echo "TCP connectivity: OK"
else
  echo "TCP connectivity: WARNING/FAILED"
  echo "Config file was created, but host/port was not reachable from this machine."
fi
