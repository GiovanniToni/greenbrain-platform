#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Uso: build_customer_local_universal_installer.sh <version>}"
ROOT="/opt/greenbrain-platform"
REL="$ROOT/releases/customer-local/$VERSION"
TAR="$REL/customer-local-$VERSION.tar.gz"
OUT_DIR="$REL/universal-installer"
ZIP="$REL/GreenBrain-Installer.zip"

[ -f "$TAR" ] || { echo "ERRORE: manca $TAR"; exit 1; }

rm -rf "$OUT_DIR" "$ZIP"
mkdir -p "$OUT_DIR"

make_script() {
  local out="$1"
  local title="$2"

  cat > "$out" <<HEADER
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="\${HOME}/GreenBrain-Customer-Local"
mkdir -p "\$APP_DIR"

echo "======================================"
echo "   $title"
echo "======================================"
echo
echo "Estraggo GreenBrain in:"
echo "  \$APP_DIR"
echo

ARCHIVE_LINE=\$(awk '/^__GREENBRAIN_ARCHIVE_BELOW__$/ {print NR + 1; exit 0;}' "\$0")
tail -n +"\$ARCHIVE_LINE" "\$0" | tar -xz -C "\$APP_DIR" --strip-components=1

cd "\$APP_DIR/customer-local-template" 2>/dev/null || cd "\$APP_DIR"

chmod +x INSTALL_GREENBRAIN.sh install.sh 2>/dev/null || true

echo
echo "Avvio wizard GreenBrain..."
echo

exec bash ./INSTALL_GREENBRAIN.sh

exit 0
__GREENBRAIN_ARCHIVE_BELOW__
HEADER

  cat "$TAR" >> "$out"
  chmod +x "$out"
}

make_script "$OUT_DIR/INSTALLA_GREENBRAIN_LINUX.run" "GreenBrain Installer Linux"
make_script "$OUT_DIR/INSTALLA_GREENBRAIN_MAC.command" "GreenBrain Installer macOS"

cat > "$OUT_DIR/INSTALLA_GREENBRAIN_WINDOWS.bat" <<'BAT'
@echo off
setlocal

echo ======================================
echo    GreenBrain Installer Windows
echo ======================================
echo.

where wsl >nul 2>nul
if errorlevel 1 (
  echo ERRORE: WSL non trovato.
  echo.
  echo GreenBrain su Windows richiede WSL + Docker Desktop.
  echo Apro la guida Microsoft per installare WSL...
  start https://learn.microsoft.com/windows/wsl/install
  pause
  exit /b 1
)

set "SCRIPT_DIR=%~dp0"

for /f "delims=" %%i in ('wsl wslpath -a "%SCRIPT_DIR%"') do set "WSL_DIR=%%i"

echo Avvio installer GreenBrain tramite WSL...
echo Cartella: %SCRIPT_DIR%
echo.

wsl bash -lc "cd '%WSL_DIR%' && chmod +x INSTALLA_GREENBRAIN_LINUX.run && ./INSTALLA_GREENBRAIN_LINUX.run"

echo.
echo Installazione terminata.
pause
BAT

if [ -f "$ROOT/deploy/customer-local-template/GreenBrain-Install.desktop" ]; then
  cp "$ROOT/deploy/customer-local-template/GreenBrain-Install.desktop" "$OUT_DIR/GreenBrain-Install.desktop"
  chmod +x "$OUT_DIR/GreenBrain-Install.desktop"
fi

cat > "$OUT_DIR/LEGGIMI_INSTALLAZIONE.txt" <<TXT
GREENBRAIN INSTALLER

Su macOS:
1) Apri questa cartella.
2) Doppio click su INSTALLA_GREENBRAIN_MAC.command.
3) Se macOS blocca il file: tasto destro > Apri.

Su Linux:
1) Doppio click su INSTALLA_GREENBRAIN_LINUX.run
   oppure da terminale:
   chmod +x INSTALLA_GREENBRAIN_LINUX.run
   ./INSTALLA_GREENBRAIN_LINUX.run

Requisiti:
- Docker installato
- Docker Compose disponibile
- Python 3 disponibile

I dati cliente restano locali.
GreenBrain centrale gestisce login, routing, heartbeat e visualizzazione autorizzata.
TXT

python3 - <<PY
from pathlib import Path
import zipfile

out_dir = Path("$OUT_DIR")
zip_path = Path("$ZIP")

with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as z:
    for p in out_dir.iterdir():
        z.write(p, arcname=p.name)

print(f"Universal installer pronto: {zip_path}")
PY
