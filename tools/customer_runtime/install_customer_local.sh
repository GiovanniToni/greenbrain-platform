#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Uso:"
  echo "  install_customer_local.sh <release_version> <target_dir>"
  exit 1
fi

VERSION="$1"
TARGET_DIR="$2"
ROOT="/opt/greenbrain-platform"
ARCHIVE="$ROOT/releases/customer-local/$VERSION/customer-local-$VERSION.tar.gz"
WORKDIR="$TARGET_DIR/customer-local-$VERSION"

fail() {
  echo "ERRORE: $1" >&2
  exit 1
}

[ -f "$ARCHIVE" ] || fail "Archivio release non trovato: $ARCHIVE"

mkdir -p "$WORKDIR"
tar -xzf "$ARCHIVE" -C "$WORKDIR"

echo "Release estratta in: $WORKDIR"
echo
echo "Prossimi passi manuali:"
echo "1) copiare env/customer-local.env.example in overlay/env/customer-local.env"
echo "2) compilare customer-local.env"
echo "3) compilare overlay tunnel"
echo "4) registrare tenant centrale"
echo "5) avviare docker compose locale"
