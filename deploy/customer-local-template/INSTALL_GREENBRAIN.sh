#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "======================================"
echo "   GreenBrain Customer Local Installer"
echo "======================================"
echo

chmod +x install.sh || true

pick_wizard_port() {
  # If the user explicitly set a port, respect it.
  if [ -n "${GREENBRAIN_INSTALLER_WIZARD_PORT:-}" ]; then
    echo "$GREENBRAIN_INSTALLER_WIZARD_PORT"
    return 0
  fi

  for port in 8099 8100 8101 8110; do
    if command -v lsof >/dev/null 2>&1; then
      if ! lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
        echo "$port"
        return 0
      fi
    elif command -v ss >/dev/null 2>&1; then
      if ! ss -ltn | awk '{print $4}' | grep -Eq "[:.]${port}$"; then
        echo "$port"
        return 0
      fi
    else
      echo "$port"
      return 0
    fi
  done

  echo "8099"
}

if [ -f "$ROOT/base/apps/local-installer-wizard/wizard.py" ] && command -v python3 >/dev/null 2>&1; then
  WIZARD_PORT="$(pick_wizard_port)"
  export GREENBRAIN_INSTALLER_WIZARD_PORT="$WIZARD_PORT"
  WIZARD_URL="http://localhost:${WIZARD_PORT}"

  echo "Avvio wizard grafico locale..."
  echo "Se il browser non si apre, visita:"
  echo "  $WIZARD_URL"
  echo

  if grep -qi microsoft /proc/version 2>/dev/null; then
    echo "Ambiente WSL rilevato: apro browser Windows..."
    explorer.exe "$WIZARD_URL" >/dev/null 2>&1 || true
  fi

  exec python3 "$ROOT/base/apps/local-installer-wizard/wizard.py"
fi

echo "Wizard grafico non disponibile. Avvio installazione terminale."
bash install.sh

echo
echo "Apri GreenBrain qui:"
echo "  http://localhost:8088"
