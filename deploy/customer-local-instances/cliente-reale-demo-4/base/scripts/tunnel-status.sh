#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Local backend ==="
curl -s http://127.0.0.1:8008/health || true
echo
echo "=== Local frontend ==="
curl -I http://127.0.0.1:8088 || true
echo
echo "=== Tunnel config dir ==="
ls -lah "$BASE_DIR/tunnel/cloudflared" || true
echo
echo "=== Tunnel config file ==="
sed -n '1,120p' "$BASE_DIR/tunnel/cloudflared/config.yml" || true
