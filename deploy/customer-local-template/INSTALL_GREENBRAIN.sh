#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "======================================"
echo "   GreenBrain Customer Local Installer"
echo "======================================"
echo

chmod +x install.sh || true

bash install.sh

echo
echo "======================================"
echo "   Installazione completata"
echo "======================================"
echo
echo "Apri GreenBrain qui:"
echo "  http://127.0.0.1:8088"
echo
echo "Per verificare lo stato:"
echo "  bash base/scripts/post-install-check.sh"
echo
