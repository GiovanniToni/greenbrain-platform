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
  bash "$ROOT/base/scripts/wizard/generate-runtime-env.sh"

  echo
  echo "Provisioning file generated."
  echo "Review it if needed, then rerun install.sh"
  exit 10
fi

chmod +x "$ROOT"/base/scripts/*.sh

"$ROOT/base/scripts/provision-local.sh"

docker compose \
  -f "$ROOT/docker-compose.local.yml" \
  --env-file "$ROOT/overlay/env/customer-local.env" \
  up -d --build

echo
echo "== WAIT BACKEND HEALTH =="
set -a
source "$ROOT/overlay/env/customer-local.env"
set +a

OK=0
for i in $(seq 1 45); do
  if curl -fsS "http://127.0.0.1:${LOCAL_BACKEND_PORT:-8008}/health" >/dev/null 2>&1; then
    echo "Backend healthy"
    OK=1
    break
  fi
  sleep 2
done

if [ "$OK" -ne 1 ]; then
  echo "ERROR: backend not healthy after install"
  docker compose -f "$ROOT/docker-compose.local.yml" --env-file "$ROOT/overlay/env/customer-local.env" ps
  exit 20
fi

"$ROOT/base/scripts/doctor-local.sh"

echo
echo "INSTALL COMPLETED"
