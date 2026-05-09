#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "== GreenBrain Customer Local Installer =="

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker missing"
  exit 1
fi

if ! command -v docker compose >/dev/null 2>&1; then
  echo "ERROR: docker compose missing"
  exit 2
fi

mkdir -p "$ROOT/overlay/env"

if [ ! -f "$ROOT/overlay/env/customer-local.env" ]; then
  if [ -f "$ROOT/env/customer-local.env.example" ]; then
    cp "$ROOT/env/customer-local.env.example" "$ROOT/overlay/env/customer-local.env"
  else
    echo "ERROR: missing $ROOT/env/customer-local.env.example"
    exit 3
  fi
fi

if [ ! -f "$ROOT/overlay/provisioning/local-runtime.env" ]; then
  cp \
    "$ROOT/overlay/provisioning/local-runtime.env.example" \
    "$ROOT/overlay/provisioning/local-runtime.env"

  echo
  echo "EDIT:"
  echo "  $ROOT/overlay/provisioning/local-runtime.env"
  echo
  echo "Then rerun install.sh"
  exit 10
fi

chmod +x "$ROOT"/base/scripts/*.sh

"$ROOT/base/scripts/provision-local.sh"

docker compose \
  -f "$ROOT/docker-compose.local.yml" \
  --env-file "$ROOT/overlay/env/customer-local.env" \
  up -d --build

"$ROOT/base/scripts/doctor-local.sh"

echo
echo "INSTALL COMPLETED"
