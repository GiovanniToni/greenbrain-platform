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
PKGDIR="$WORKDIR/package/customer-local-template"

fail() {
  echo "ERRORE: $1" >&2
  exit 1
}

ok() {
  echo "OK: $1"
}

[ -f "$ARCHIVE" ] || fail "Archivio release non trovato: $ARCHIVE"

mkdir -p "$WORKDIR"
rm -rf "$WORKDIR"/*
tar -xzf "$ARCHIVE" -C "$WORKDIR"

[ -d "$PKGDIR" ] || fail "Package estratto non valido: manca $PKGDIR"
[ -f "$PKGDIR/VERSION" ] || fail "Package estratto non valido: manca VERSION"
[ -f "$PKGDIR/release-manifest.yml" ] || fail "Package estratto non valido: manca release-manifest.yml"
[ -f "$PKGDIR/docker-compose.local.yml" ] || fail "Package estratto non valido: manca docker-compose.local.yml"
[ -f "$PKGDIR/env/customer-local.env.example" ] || fail "Package estratto non valido: manca env/customer-local.env.example"
[ -d "$PKGDIR/base/backend-src" ] || fail "Package estratto non valido: manca base/backend-src"
[ -d "$PKGDIR/base/frontend-dist" ] || fail "Package estratto non valido: manca base/frontend-dist"

ok "release estratta e verificata"

mkdir -p "$PKGDIR/overlay/env"
mkdir -p "$PKGDIR/overlay/tunnel/cloudflared"

if [ ! -f "$PKGDIR/overlay/env/customer-local.env" ]; then
  cp "$PKGDIR/env/customer-local.env.example" "$PKGDIR/overlay/env/customer-local.env"
  echo "CREATED: overlay/env/customer-local.env from example"
fi

if [ ! -f "$PKGDIR/overlay/tunnel/cloudflared/config.yml" ] && [ -f "$PKGDIR/tunnel/cloudflared/config.yml.example" ]; then
  cp "$PKGDIR/tunnel/cloudflared/config.yml.example" "$PKGDIR/overlay/tunnel/cloudflared/config.yml"
  echo "CREATED: overlay/tunnel/cloudflared/config.yml from example"
fi

if [ ! -f "$PKGDIR/overlay/tunnel/cloudflared/cloudflared.env" ] && [ -f "$PKGDIR/tunnel/cloudflared/cloudflared.env.example" ]; then
  cp "$PKGDIR/tunnel/cloudflared/cloudflared.env.example" "$PKGDIR/overlay/tunnel/cloudflared/cloudflared.env"
  echo "CREATED: overlay/tunnel/cloudflared/cloudflared.env from example"
fi


echo
echo "Release pronta in:"
echo "  $PKGDIR"

echo
echo "File da compilare / preparare:"
echo "  $PKGDIR/overlay/env/customer-local.env            (da creare copiando l'example)"
echo "  $PKGDIR/overlay/tunnel/cloudflared/config.yml     (da creare da example)"
echo "  $PKGDIR/overlay/tunnel/cloudflared/cloudflared.env (da creare da example)"

echo
echo "Comandi suggeriti:"
echo "  cp $PKGDIR/env/customer-local.env.example $PKGDIR/overlay/env/customer-local.env"
echo "  cp $PKGDIR/tunnel/cloudflared/config.yml.example $PKGDIR/overlay/tunnel/cloudflared/config.yml"
echo "  cp $PKGDIR/tunnel/cloudflared/cloudflared.env.example $PKGDIR/overlay/tunnel/cloudflared/cloudflared.env"

echo
echo "Poi:"
echo "  1) compilare i file overlay con i valori del cliente"
echo "  2) registrare il tenant centrale"
echo "  3) avviare il docker compose locale"
