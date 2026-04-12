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

echo "== Aggiorna versione template sorgente =="
echo "$VERSION" > "$TEMPLATE/VERSION"

python3 - <<PY
from pathlib import Path
import re

p = Path("$TEMPLATE/release-manifest.yml")
s = p.read_text()
s = re.sub(r'^package_version:.*$', 'package_version: $VERSION', s, flags=re.M)
p.write_text(s)
print("UPDATED", p)
PY

echo "== Verifica frontend build =="
if [ ! -f "$ROOT/apps/frontend/dist/index.html" ]; then
  echo "Frontend dist mancante: lancio build"
  cd "$ROOT/apps/frontend"
  npm run build
else
  echo "Frontend dist già presente: uso artefatti esistenti"
fi

echo "== Sync frontend/backend nel template =="
mkdir -p "$TEMPLATE/frontend-dist"
mkdir -p "$TEMPLATE/backend-src"

rsync -a --delete "$ROOT/apps/frontend/dist/" "$TEMPLATE/frontend-dist/"
rsync -a --delete "$ROOT/apps/backend/" "$TEMPLATE/backend-src/"

echo "== Copia template nella release =="
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
