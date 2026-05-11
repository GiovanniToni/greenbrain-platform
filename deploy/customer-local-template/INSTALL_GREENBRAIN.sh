#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "======================================"
echo "   GreenBrain Customer Local Installer"
echo "======================================"
echo

cd "$ROOT"
bash install.sh

echo
echo "Installazione completata."
echo "Per verificare lo stato:"
echo "  bash base/scripts/post-install-check.sh"
