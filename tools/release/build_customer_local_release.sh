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

rm -f "$PKG/overlay/env/customer-local.env"
rm -f "$PKG/base/backend-src/.env"
rm -f "$PKG/overlay/tunnel/cloudflared/cloudflared.env"

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
