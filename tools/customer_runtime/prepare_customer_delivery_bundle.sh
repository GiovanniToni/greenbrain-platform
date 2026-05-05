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

mkdir -p "$DELIVERY_DIR/tools/customer_runtime"
cp "$ROOT/tools/customer_runtime/install_customer_local.sh" "$DELIVERY_DIR/tools/customer_runtime/"
cp "$ROOT/tools/customer_runtime/install_customer_local_from_bundle.sh" "$DELIVERY_DIR/tools/customer_runtime/"
cp "$ROOT/tools/customer_runtime/update_customer_local_from_bundle.sh" "$DELIVERY_DIR/tools/customer_runtime/"

cat > "$DELIVERY_DIR/README-INSTALL.txt" <<README
GreenBrain Customer Local - Release $VERSION

Contenuto:
- customer-local-$VERSION.tar.gz
- tools/customer_runtime/install_customer_local.sh
- tools/customer_runtime/install_customer_local_from_bundle.sh
- tools/customer_runtime/update_customer_local_from_bundle.sh

Installazione consigliata:
1. eseguire:
   bash tools/customer_runtime/install_customer_local.sh $VERSION /opt/greenbrain-customer
2. lo script estrae il pacchetto e crea automaticamente:
   overlay/env/customer-local.env
   overlay/tunnel/cloudflared/config.yml
   overlay/tunnel/cloudflared/cloudflared.env
3. compilare questi file con i valori reali del cliente
4. validare il compose
5. avviare il runtime locale
6. completare registrazione tenant, tunnel e DB sorgente con supporto GreenBrain

Nota:
i file overlay reali sono customer-specific e non vengono sovrascritti automaticamente negli update.
README

echo "Bundle consegnabile pronto in:"
echo "  $DELIVERY_DIR"
