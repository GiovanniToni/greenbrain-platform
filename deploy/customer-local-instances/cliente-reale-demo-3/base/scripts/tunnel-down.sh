#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

docker compose -f "$BASE_DIR/tunnel/docker-compose.tunnel.yml" down

echo "Tunnel container fermato."
