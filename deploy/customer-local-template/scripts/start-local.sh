#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$BASE_DIR"
docker compose -f docker-compose.local.yml up -d --build

echo
echo "GreenBrain locale avviato."
echo "Frontend locale: http://127.0.0.1:8088"
echo "Backend locale:  http://127.0.0.1:8008"
