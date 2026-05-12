#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Uso: build_customer_local_macos_oneclick.sh <version>}"
ROOT="/opt/greenbrain-platform"
REL="$ROOT/releases/customer-local/$VERSION"
TAR="$REL/customer-local-$VERSION.tar.gz"
OUT_DIR="$REL/macos-installer"
COMMAND="$OUT_DIR/INSTALLA_GREENBRAIN.command"
ZIP="$REL/INSTALLA_GREENBRAIN_MAC.zip"

[ -f "$TAR" ] || { echo "ERRORE: manca $TAR"; exit 1; }

rm -rf "$OUT_DIR" "$ZIP"
mkdir -p "$OUT_DIR"

cat > "$COMMAND" <<'HEADER'
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${HOME}/GreenBrain-Customer-Local"
mkdir -p "$APP_DIR"

echo "======================================"
echo "   GreenBrain Installer macOS"
echo "======================================"
echo
echo "Estraggo GreenBrain in:"
echo "  $APP_DIR"
echo

ARCHIVE_LINE=$(awk '/^__GREENBRAIN_ARCHIVE_BELOW__$/ {print NR + 1; exit 0;}' "$0")
tail -n +"$ARCHIVE_LINE" "$0" | tar -xz -C "$APP_DIR" --strip-components=1

cd "$APP_DIR/customer-local-template" 2>/dev/null || cd "$APP_DIR"

chmod +x INSTALL_GREENBRAIN.sh install.sh 2>/dev/null || true

echo
echo "Avvio wizard GreenBrain..."
echo

exec bash ./INSTALL_GREENBRAIN.sh

exit 0
__GREENBRAIN_ARCHIVE_BELOW__
HEADER

cat "$TAR" >> "$COMMAND"
chmod +x "$COMMAND"

(
  cd "$OUT_DIR"
  zip -q "../INSTALLA_GREENBRAIN_MAC.zip" "INSTALLA_GREENBRAIN.command"
)

echo "macOS one-click installer pronto:"
echo "  $ZIP"
