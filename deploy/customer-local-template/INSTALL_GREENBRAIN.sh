#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "======================================"
echo "   GreenBrain Customer Local Installer"
echo "======================================"
echo

chmod +x install.sh || true

if [ -f "$ROOT/base/apps/local-installer-wizard/wizard.py" ] && command -v python3 >/dev/null 2>&1; then
  echo "Avvio wizard grafico locale..."
  echo "Se il browser non si apre, visita:"
  echo "  http://127.0.0.1:${GREENBRAIN_INSTALLER_WIZARD_PORT:-8099}"
  echo

  if grep -qi microsoft /proc/version 2>/dev/null; then
    echo "Ambiente WSL rilevato: apro browser Windows..."
    explorer.exe "http://127.0.0.1:${GREENBRAIN_INSTALLER_WIZARD_PORT:-8099}" >/dev/null 2>&1 || true
  fi

  exec python3 "$ROOT/base/apps/local-installer-wizard/wizard.py"
fi

echo "Wizard grafico non disponibile. Avvio installazione terminale."
bash install.sh

echo
echo "Apri GreenBrain qui:"
echo "  http://127.0.0.1:8088"
