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

mkdir -p "$STAGING"

echo "== Copia template già validato nella release =="
cp -R "$TEMPLATE" "$STAGING/customer-local-template"

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
