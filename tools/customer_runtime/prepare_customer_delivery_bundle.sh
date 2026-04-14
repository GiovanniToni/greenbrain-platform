#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Uso:"
  echo "  prepare_customer_delivery_bundle.sh <release_version> <output_dir>"
  exit 1
fi

VERSION="$1"
OUTPUT_DIR="$2"
ROOT="/opt/greenbrain-platform"
ARCHIVE="$ROOT/releases/customer-local/$VERSION/customer-local-$VERSION.tar.gz"
DELIVERY_DIR="$OUTPUT_DIR/greenbrain-customer-local-$VERSION"

fail() {
  echo "ERRORE: $1" >&2
  exit 1
}

[ -f "$ARCHIVE" ] || fail "Archivio release non trovato: $ARCHIVE"

rm -rf "$DELIVERY_DIR"
mkdir -p "$DELIVERY_DIR"

cp "$ARCHIVE" "$DELIVERY_DIR/"

cat > "$DELIVERY_DIR/README-INSTALL.txt" <<README
GreenBrain Customer Local - Release $VERSION

Contenuto:
- customer-local-$VERSION.tar.gz

Passi:
1. estrarre il tar.gz
2. copiare:
   env/customer-local.env.example -> overlay/env/customer-local.env
   tunnel/cloudflared/config.yml.example -> overlay/tunnel/cloudflared/config.yml
   tunnel/cloudflared/cloudflared.env.example -> overlay/tunnel/cloudflared/cloudflared.env
3. compilare i file con i valori reali del cliente
4. validare il compose
5. avviare il runtime locale
6. completare registrazione tenant, tunnel e DB sorgente con supporto GreenBrain
README

echo "Bundle consegnabile pronto in:"
echo "  $DELIVERY_DIR"
