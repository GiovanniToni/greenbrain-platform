#!/usr/bin/env bash
set -euo pipefail

BASE=/opt/greenbrain-platform
RELEASE_DIR="$BASE/client-runtime/release"

if [ $# -lt 1 ]; then
  echo "Usage: $0 /path/to/package_dir"
  exit 1
fi

PKG_DIR="$1"

if [ ! -d "$PKG_DIR" ]; then
  echo "Package dir not found: $PKG_DIR"
  exit 1
fi

SNAP_DIR="$BASE/_snapshots/client_update_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$SNAP_DIR"

echo "=== SNAPSHOT CURRENT FILES ==="
while IFS= read -r relpath; do
  [ -z "$relpath" ] && continue
  src="$BASE/$relpath"
  if [ -f "$src" ]; then
    dst="$SNAP_DIR/$relpath"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
  fi
done < "$RELEASE_DIR/runtime_manifest.txt"

echo "=== APPLY PACKAGE FILES ==="
while IFS= read -r relpath; do
  [ -z "$relpath" ] && continue

  src="$PKG_DIR/$relpath"
  dst="$BASE/$relpath"

  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "UPDATED $relpath"
  else
    echo "WARN missing in package: $relpath"
  fi
done < "$RELEASE_DIR/runtime_manifest.txt"

echo "=== APPLY SQL ==="
set -a
source "$BASE/client-runtime/etl/.env.ml.runtime"
set +a
export PGPASSWORD="$PG_PASSWORD"

for sql in \
  client-runtime/sql/init/21_ml_ops_runtime_fix.sql \
  client-runtime/sql/init/22_ml_strength_runtime_fix.sql \
  client-runtime/sql/init/23_ml_forecast_routing_runtime_fix.sql \
  client-runtime/sql/init/24_ml_forecast_routing_v4_preferred.sql
do
  if [ -f "$BASE/$sql" ]; then
    echo "APPLY $sql"
    psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -f "$BASE/$sql"
  fi
done

echo "=== VALIDATE UPDATED RUNTIME ==="
"$BASE/client-runtime/scripts/validate_client_runtime.sh"

echo "SNAPSHOT_DIR=$SNAP_DIR"
echo "UPDATE_DONE"
