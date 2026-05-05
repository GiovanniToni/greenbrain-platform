#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Uso:"
  echo "  install_customer_local_from_bundle.sh <bundle_dir> <target_instance_dir>"
  exit 1
fi

BUNDLE_DIR="$1"
TARGET_DIR="$2"

fail() {
  echo "ERRORE: $1" >&2
  exit 1
}

ok() {
  echo "OK: $1"
}

[ -d "$BUNDLE_DIR" ] || fail "Bundle dir non trovata: $BUNDLE_DIR"
[ -f "$BUNDLE_DIR/VERSION" ] || fail "Bundle non valido: manca VERSION"
[ -f "$BUNDLE_DIR/release-manifest.yml" ] || fail "Bundle non valido: manca release-manifest.yml"
[ -f "$BUNDLE_DIR/docker-compose.local.yml" ] || fail "Bundle non valido: manca docker-compose.local.yml"
[ -d "$BUNDLE_DIR/base" ] || fail "Bundle non valido: manca base/"
[ -d "$BUNDLE_DIR/env" ] || fail "Bundle non valido: manca env/"
[ -d "$BUNDLE_DIR/overlay" ] || fail "Bundle non valido: manca overlay/"
[ -d "$BUNDLE_DIR/tunnel" ] || fail "Bundle non valido: manca tunnel/"

if [ -e "$TARGET_DIR" ]; then
  fail "Target già esistente: $TARGET_DIR"
fi

mkdir -p "$TARGET_DIR"
cp -R "$BUNDLE_DIR/." "$TARGET_DIR/"

mkdir -p "$TARGET_DIR/overlay/env"
mkdir -p "$TARGET_DIR/overlay/tunnel/cloudflared"

ok "bundle copiato in $TARGET_DIR"

if [ ! -f "$TARGET_DIR/overlay/env/customer-local.env" ]; then
  cp "$TARGET_DIR/env/customer-local.env.example" "$TARGET_DIR/overlay/env/customer-local.env"
  echo "CREATED: overlay/env/customer-local.env from example"
fi

if [ ! -f "$TARGET_DIR/overlay/tunnel/cloudflared/config.yml" ] && [ -f "$TARGET_DIR/tunnel/cloudflared/config.yml.example" ]; then
  cp "$TARGET_DIR/tunnel/cloudflared/config.yml.example" "$TARGET_DIR/overlay/tunnel/cloudflared/config.yml"
  echo "CREATED: overlay/tunnel/cloudflared/config.yml from example"
fi

if [ ! -f "$TARGET_DIR/overlay/tunnel/cloudflared/cloudflared.env" ] && [ -f "$TARGET_DIR/tunnel/cloudflared/cloudflared.env.example" ]; then
  cp "$TARGET_DIR/tunnel/cloudflared/cloudflared.env.example" "$TARGET_DIR/overlay/tunnel/cloudflared/cloudflared.env"
  echo "CREATED: overlay/tunnel/cloudflared/cloudflared.env from example"
fi


echo
echo "Prossimi passi:"
echo "  cp $TARGET_DIR/env/customer-local.env.example $TARGET_DIR/overlay/env/customer-local.env"
echo "  cp $TARGET_DIR/tunnel/cloudflared/config.yml.example $TARGET_DIR/overlay/tunnel/cloudflared/config.yml"
echo "  cp $TARGET_DIR/tunnel/cloudflared/cloudflared.env.example $TARGET_DIR/overlay/tunnel/cloudflared/cloudflared.env"
echo
echo "Poi compilare i file overlay, validare e avviare il runtime."
