#!/usr/bin/env bash
set -euo pipefail

BASE=/opt/greenbrain-platform
OUT_DIR="$BASE/client-runtime/release"
PKG_DIR="$OUT_DIR/package_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$PKG_DIR"

while IFS= read -r relpath; do
  [ -z "$relpath" ] && continue
  src="$BASE/$relpath"
  dst="$PKG_DIR/$relpath"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
done < "$OUT_DIR/runtime_manifest.txt"

tar -czf "$PKG_DIR.tar.gz" -C "$PKG_DIR" .
echo "PACKAGE_DIR=$PKG_DIR"
echo "PACKAGE_TAR=$PKG_DIR.tar.gz"
