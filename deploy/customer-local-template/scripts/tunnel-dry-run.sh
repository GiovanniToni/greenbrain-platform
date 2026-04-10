#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Compose render ==="
docker compose -f "$BASE_DIR/tunnel/docker-compose.tunnel.yml" config

echo
echo "=== File tunnel ==="
ls -lah "$BASE_DIR/tunnel/cloudflared"

echo
echo "=== ATTENZIONE ==="
echo "Per un avvio reale serve il file credentials json valido."
echo "Questo script non avvia il tunnel."
