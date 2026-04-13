#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Uso:"
  echo "  bash tools/ops/customer_local.sh release <version> <tenant_slug>"
  echo "  bash tools/ops/customer_local.sh bootstrap <tenant_code> <tenant_slug> <tenant_host>"
  echo "  bash tools/ops/customer_local.sh validate <tenant_slug>"
  echo "  bash tools/ops/customer_local.sh status <tenant_slug>"
  echo "  bash tools/ops/customer_local.sh doctor <tenant_slug>"
  echo "  bash tools/ops/customer_local.sh list"
  exit 1
}

[ "$#" -ge 1 ] || usage

CMD="$1"
shift || true

ROOT="/opt/greenbrain-platform"

case "$CMD" in
  release)
    [ "$#" -eq 2 ] || usage
    VERSION="$1"
    SLUG="$2"
    bash "$ROOT/tools/release/release_customer_local.sh" "$VERSION" "$SLUG"
    ;;
  bootstrap)
    [ "$#" -eq 3 ] || usage
    TENANT_CODE="$1"
    TENANT_SLUG="$2"
    TENANT_HOST="$3"
    bash "$ROOT/tools/onboarding/create_customer_local_instance.sh" "$TENANT_CODE" "$TENANT_SLUG" "$TENANT_HOST"
    echo
    bash "$ROOT/tools/onboarding/validate_customer_local_instance.sh" "$TENANT_SLUG"
    ;;
  validate)
    [ "$#" -eq 1 ] || usage
    SLUG="$1"
    bash "$ROOT/tools/onboarding/validate_customer_local_instance.sh" "$SLUG"
    ;;
  list)
    [ "$#" -eq 0 ] || usage

    BASE_DIR="$ROOT/deploy/customer-local-instances"

    [ -d "$BASE_DIR" ] || {
      echo "Directory non trovata: $BASE_DIR"
      exit 1
    }

    echo "SLUG | VERSION | PACKAGE_VERSION | ENV | TUNNEL"
    echo "-----|---------|-----------------|-----|-------"

    for d in "$BASE_DIR"/*; do
      [ -d "$d" ] || continue

      SLUG="$(basename "$d")"
      VERSION="-"
      PACKAGE_VERSION="-"
      ENV_OK="no"
      TUNNEL_OK="no"

      [ -f "$d/VERSION" ] && VERSION="$(cat "$d/VERSION")"
      [ -f "$d/release-manifest.yml" ] && PACKAGE_VERSION="$(awk -F': ' '/^package_version:/{print $2}' "$d/release-manifest.yml")"
      [ -f "$d/overlay/env/customer-local.env" ] && ENV_OK="yes"
      [ -f "$d/overlay/tunnel/cloudflared/config.yml" ] && TUNNEL_OK="yes"

      echo "$SLUG | $VERSION | $PACKAGE_VERSION | $ENV_OK | $TUNNEL_OK"
    done
    ;;
  doctor)
    [ "$#" -eq 1 ] || usage
    SLUG="$1"
    INSTANCE="$ROOT/deploy/customer-local-instances/$SLUG"

    [ -d "$INSTANCE" ] || {
      echo "Istanza non trovata: $INSTANCE"
      exit 1
    }

    echo "=== DOCTOR: VERSION ==="
    cat "$INSTANCE/VERSION"
    echo
    grep '^package_version:' "$INSTANCE/release-manifest.yml"

    echo
    echo "=== DOCTOR: VALIDATE ==="
    bash "$ROOT/tools/onboarding/validate_customer_local_instance.sh" "$SLUG"

    echo
    echo "=== DOCTOR: LOCAL COMPOSE ==="
    docker compose \
      --env-file "$INSTANCE/overlay/env/customer-local.env" \
      -f "$INSTANCE/docker-compose.local.yml" \
      ps

    echo
    echo "=== DOCTOR: TUNNEL COMPOSE ==="
    docker compose \
      -f "$INSTANCE/tunnel/docker-compose.tunnel.yml" \
      ps

    echo
    echo "=== DOCTOR: POST CHECK ==="
    bash "$INSTANCE/base/scripts/post-update-check.sh"
    ;;
  status)
    [ "$#" -eq 1 ] || usage
    SLUG="$1"
    INSTANCE="$ROOT/deploy/customer-local-instances/$SLUG"
    ENV_FILE="$INSTANCE/overlay/env/customer-local.env"

    [ -d "$INSTANCE" ] || { echo "Istanza non trovata: $INSTANCE"; exit 1; }
    [ -f "$ENV_FILE" ] || { echo "Env overlay non trovato: $ENV_FILE"; exit 1; }

    echo "=== VERSION ==="
    cat "$INSTANCE/VERSION"
    echo
    grep '^package_version:' "$INSTANCE/release-manifest.yml" || true

    echo
    echo "=== VALIDATE ==="
    bash "$ROOT/tools/onboarding/validate_customer_local_instance.sh" "$SLUG"

    echo
    echo "=== LOCAL COMPOSE ==="
    docker compose \
      --env-file "$ENV_FILE" \
      -f "$INSTANCE/docker-compose.local.yml" \
      ps

    echo
    echo "=== TUNNEL COMPOSE ==="
    docker compose \
      -f "$INSTANCE/tunnel/docker-compose.tunnel.yml" \
      ps

    echo
    echo "=== POST CHECK ==="
    bash "$INSTANCE/base/scripts/post-update-check.sh"
    ;;
  *)
    usage
    ;;
esac
