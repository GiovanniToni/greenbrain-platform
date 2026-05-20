#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "== GreenBrain Customer Local Installer =="

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker missing"
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: Docker Compose plugin missing or not available"
  echo "Install Docker Compose plugin, then retry."
  exit 2
fi

mkdir -p "$ROOT/overlay/env" "$ROOT/overlay/provisioning"

if [ ! -f "$ROOT/overlay/env/customer-local.env" ]; then
  if [ -x "$ROOT/base/scripts/wizard/generate-customer-env.sh" ]; then
    bash "$ROOT/base/scripts/wizard/generate-customer-env.sh"
  elif [ -f "$ROOT/env/customer-local.env.example" ]; then
    cp "$ROOT/env/customer-local.env.example" "$ROOT/overlay/env/customer-local.env"
  else
    echo "ERROR: missing customer env generator/example"
    exit 3
  fi
fi

if [ ! -f "$ROOT/overlay/provisioning/local-runtime.env" ]; then
  bash "$ROOT/base/scripts/wizard/generate-runtime-env.sh"
fi

chmod +x "$ROOT"/base/scripts/*.sh

"$ROOT/base/scripts/preflight-local-install.sh"

"$ROOT/base/scripts/provision-local.sh"

export GREENBRAIN_IMAGE_TAG="${GREENBRAIN_IMAGE_TAG:-$(cat "$ROOT/VERSION" 2>/dev/null || echo latest)}"
echo "Docker image tag: $GREENBRAIN_IMAGE_TAG"

USE_PREBUILT="${GREENBRAIN_USE_PREBUILT_IMAGES:-1}"

compose_safe() {
  env \
    -u POSTGRES_DB \
    -u POSTGRES_USER \
    -u POSTGRES_PASSWORD \
    -u POSTGRES_HOST \
    -u POSTGRES_PORT \
    -u POSTGRES_SSLMODE \
    -u DATABASE_URL \
    -u TENANT_CODE \
    -u TENANT_NAME \
    -u TENANT_HOST \
    -u LOCAL_CUSTOMER_EMAIL \
    -u LOCAL_CUSTOMER_FULL_NAME \
    -u LOCAL_CUSTOMER_TEMP_PASSWORD \
    -u LOCAL_CUSTOMER_PASSWORD_HASH \
    -u LOCAL_CUSTOMER_PASSWORD_MODE \
    -u LOCAL_CUSTOMER_TENANT_CODE \
    -u LOCAL_CUSTOMER_HOME_HOST \
    -u LOCAL_CUSTOMER_HOME_PATH \
    docker compose "$@"
}



if [ "$USE_PREBUILT" = "1" ]; then
  echo "Using prebuilt Docker images"
  if ! compose_safe \
    -f "$ROOT/docker-compose.prebuilt.yml" \
    --env-file "$ROOT/overlay/env/customer-local.env" \
    up -d; then
    echo
    echo "WARN: prebuilt Docker image startup failed"
    echo "WARN: falling back to local Docker build"
    compose_safe \
      -f "$ROOT/docker-compose.local.yml" \
      --env-file "$ROOT/overlay/env/customer-local.env" \
      up -d --build
  fi
else
  echo "Using local Docker build"
  compose_safe \
    -f "$ROOT/docker-compose.local.yml" \
    --env-file "$ROOT/overlay/env/customer-local.env" \
    up -d --build
fi

echo
echo "== WAIT BACKEND HEALTH =="
set -a
source "$ROOT/overlay/env/customer-local.env"
set +a

OK=0
for i in $(seq 1 45); do
  if curl -fsS "http://localhost:${LOCAL_BACKEND_PORT:-8008}/health" >/dev/null 2>&1; then
    echo "Backend healthy"
    OK=1
    break
  fi
  sleep 2
done

if [ "$OK" -ne 1 ]; then
  echo "ERROR: backend not healthy after install"
  if [ "${USE_PREBUILT:-1}" = "1" ] && [ -f "$ROOT/docker-compose.prebuilt.yml" ]; then
    compose_safe -f "$ROOT/docker-compose.prebuilt.yml" --env-file "$ROOT/overlay/env/customer-local.env" ps || true
  fi
  compose_safe -f "$ROOT/docker-compose.local.yml" --env-file "$ROOT/overlay/env/customer-local.env" ps || true
  exit 20
fi

"$ROOT/base/scripts/provision-local-user.sh"

"$ROOT/base/scripts/doctor-local.sh"

echo
echo
CONFIG_SOURCE_DB="${GREENBRAIN_CONFIGURE_SOURCE_DB:-}"
if [ -z "$CONFIG_SOURCE_DB" ]; then
  read -r -p "Configure Source DB now? yes/no [no]: " CONFIG_SOURCE_DB || CONFIG_SOURCE_DB="no"
fi
CONFIG_SOURCE_DB="${CONFIG_SOURCE_DB:-no}"

if [ "$CONFIG_SOURCE_DB" = "yes" ] || [ "$CONFIG_SOURCE_DB" = "y" ]; then
  bash "$ROOT/base/scripts/generate-source-db-env.sh"
else
  echo "Source DB configuration skipped. You can run later:"
  echo "  bash base/scripts/generate-source-db-env.sh"
fi

echo
echo "== INSTALL SUMMARY =="
echo "VERSION: $(cat "$ROOT/VERSION" 2>/dev/null || echo unknown)"
echo "Customer env: $ROOT/overlay/env/customer-local.env"
echo "Runtime env: $ROOT/overlay/provisioning/local-runtime.env"
if [ -f "$ROOT/overlay/env/source-db.env" ]; then
  echo "Source DB: configured"
else
  echo "Source DB: not configured"
fi
echo "Backend URL: http://localhost:${LOCAL_BACKEND_PORT:-8008}/health"
echo "Frontend URL: http://localhost:${LOCAL_FRONTEND_PORT:-8088}"
echo
echo "INSTALL COMPLETED"
