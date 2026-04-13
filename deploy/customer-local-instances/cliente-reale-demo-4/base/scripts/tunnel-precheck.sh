#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Backend locale ==="
curl -i http://127.0.0.1:8008/health
echo
echo "=== Frontend locale ==="
curl -I http://127.0.0.1:8088
echo
echo "=== Cloudflared env ==="
sed -n '1,120p' "$BASE_DIR/tunnel/cloudflared/cloudflared.env"
echo
echo "=== Cloudflared config ==="
sed -n '1,120p' "$BASE_DIR/tunnel/cloudflared/config.yml"
echo
echo "=== Tunnel compose render ==="
docker compose -f "$BASE_DIR/tunnel/docker-compose.tunnel.yml" config
