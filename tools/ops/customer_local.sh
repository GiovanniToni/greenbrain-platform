#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Uso:"
  echo "  bash tools/ops/customer_local.sh release <version> <tenant_slug>"
  echo "  bash tools/ops/customer_local.sh bootstrap <tenant_code> <tenant_slug> <tenant_host>"
  echo "  bash tools/ops/customer_local.sh validate <tenant_slug>"
  echo "  bash tools/ops/customer_local.sh status <tenant_slug>"
  echo "  bash tools/ops/customer_local.sh doctor <tenant_slug>"
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
