#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$ROOT/overlay/logs/source-db"

mkdir -p "$LOG_DIR"

# source-db-importer can run as uid/gid 1000.
# chown may fail on some host filesystems; keep it non-blocking.
chown -R 1000:1000 "$LOG_DIR" 2>/dev/null || true
chmod -R u+rwX,g+rwX,o+rwX "$LOG_DIR" 2>/dev/null || true

echo "SOURCE_DB_LOG_PERMISSIONS_OK path=$LOG_DIR"
