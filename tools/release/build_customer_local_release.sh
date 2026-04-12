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

if [ -d "$OUTDIR" ]; then
  echo "Release già esistente: $OUTDIR"
  exit 1
fi

mkdir -p "$STAGING"

echo "== Build frontend =="
cd "$ROOT/apps/frontend"
npm run build

echo "== Copia template =="
cp -R "$TEMPLATE" "$STAGING/customer-local-template"

echo "== Copia frontend build =="
mkdir -p "$STAGING/customer-local-template/frontend-dist"
cp -R "$ROOT/apps/frontend/dist/." "$STAGING/customer-local-template/frontend-dist/"

echo "== Copia backend sorgente runtime =="
mkdir -p "$STAGING/customer-local-template/backend-src"
cp -R "$ROOT/apps/backend/." "$STAGING/customer-local-template/backend-src/"

echo "== Scrittura versione =="
echo "$VERSION" > "$STAGING/customer-local-template/VERSION"

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
