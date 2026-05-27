#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Uso:"
  echo "  build_customer_local_release.sh <version>"
  exit 1
fi

VERSION="$1"
ROOT="/opt/greenbrain-platform"
TEMPLATE="$ROOT/deploy/customer-local-template"
OUTDIR="$ROOT/releases/customer-local/$VERSION"
STAGING="$OUTDIR/package"
PKG="$STAGING/customer-local-template"

fail() {
  echo "ERRORE: $1" >&2
  exit 1
}

[ -d "$TEMPLATE" ] || fail "Template non trovato: $TEMPLATE"

TV="$(cat "$TEMPLATE/VERSION")"
MV="$(awk -F': ' '/^package_version:/{print $2}' "$TEMPLATE/release-manifest.yml")"

[ "$TV" = "$VERSION" ] || fail "VERSION template ($TV) diversa da release richiesta ($VERSION)"
[ "$MV" = "$VERSION" ] || fail "package_version template ($MV) diversa da release richiesta ($VERSION)"

if [ -d "$OUTDIR" ]; then
  echo "Release già esistente: $OUTDIR"
  exit 1
fi

mkdir -p "$PKG"

echo "== Copia package pulito =="

# file root da mantenere
cp "$TEMPLATE/README.md" "$PKG/README.md"
cp "$TEMPLATE/VERSION" "$PKG/VERSION"
cp "$TEMPLATE/release-manifest.yml" "$PKG/release-manifest.yml"
cp "$TEMPLATE/base-overlay-model.md" "$PKG/base-overlay-model.md"
cp "$TEMPLATE/docker-compose.local.yml" "$PKG/docker-compose.local.yml"
if [ -f "$TEMPLATE/docker-compose.prebuilt.yml" ]; then
  cp "$TEMPLATE/docker-compose.prebuilt.yml" "$PKG/docker-compose.prebuilt.yml"
fi
cp "$TEMPLATE/install.sh" "$PKG/install.sh"
chmod +x "$PKG/install.sh"

# launcher utente finale
if [ -f "$TEMPLATE/INSTALL_GREENBRAIN.sh" ]; then
  cp "$TEMPLATE/INSTALL_GREENBRAIN.sh" "$PKG/INSTALL_GREENBRAIN.sh"
  chmod +x "$PKG/INSTALL_GREENBRAIN.sh"
fi

if [ -f "$TEMPLATE/GreenBrain-Install.desktop" ]; then
  cp "$TEMPLATE/GreenBrain-Install.desktop" "$PKG/GreenBrain-Install.desktop"
  chmod +x "$PKG/GreenBrain-Install.desktop"
fi

if [ -f "$TEMPLATE/INSTALLA GREENBRAIN.desktop" ]; then
  cp "$TEMPLATE/INSTALLA GREENBRAIN.desktop" "$PKG/INSTALLA GREENBRAIN.desktop"
  chmod +x "$PKG/INSTALLA GREENBRAIN.desktop"
fi

if [ -f "$TEMPLATE/COME_INSTALLARE_GREENBRAIN.txt" ]; then
  cp "$TEMPLATE/COME_INSTALLARE_GREENBRAIN.txt" "$PKG/COME_INSTALLARE_GREENBRAIN.txt"
fi

# directory canoniche da mantenere
cp -R "$TEMPLATE/base" "$PKG/base"
cp -R "$TEMPLATE/env" "$PKG/env"
cp -R "$TEMPLATE/overlay" "$PKG/overlay"
cp -R "$TEMPLATE/tunnel" "$PKG/tunnel"

# rimuovi eventuali file non desiderati finiti nel package
rm -rf "$PKG/backend-src" \
       "$PKG/scripts" \
       "$PKG/desktop" \
       "$PKG/systemd" \
       "$PKG/frontend-nginx"

# rimuovi file/cache/backup/test non desiderati dal package staging
find "$PKG" -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
find "$PKG" -type f -name "*.pyc" -delete 2>/dev/null || true
find "$PKG" -type f \( -name "*.bak" -o -name "*.bak_*" -o -name "*~" \) -delete 2>/dev/null || true

rm -rf "$PKG/venv" 2>/dev/null || true
rm -rf "$PKG/overlay/logs" 2>/dev/null || true

rm -f "$PKG/overlay/env/customer-local.env"
rm -f "$PKG/overlay/provisioning/local-runtime.env"
rm -f "$PKG/base/backend-src/.env"
rm -f "$PKG/overlay/tunnel/cloudflared/cloudflared.env"

mkdir -p "$PKG/overlay/env"
mkdir -p "$PKG/overlay/provisioning"

cat > "$OUTDIR/BUILD-INFO.txt" <<BUILDINFO
release_version=$VERSION
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
git_commit=$(git -C "$ROOT" rev-parse HEAD)
BUILDINFO

echo "== Archivio =="
cd "$OUTDIR"
tar -czf "customer-local-$VERSION.tar.gz" package

echo
echo "Release pronta:"
echo "  $OUTDIR/customer-local-$VERSION.tar.gz"
