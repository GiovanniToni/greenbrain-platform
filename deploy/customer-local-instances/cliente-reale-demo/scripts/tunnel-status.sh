#!/usr/bin/env bash
set -euo pipefail

echo "=== Local backend ==="
curl -s http://127.0.0.1:8008/health || true
echo
echo "=== Local frontend ==="
curl -I http://127.0.0.1:8088 || true
echo
echo "=== Tunnel config ==="
ls -lah ./tunnel/cloudflared || true
