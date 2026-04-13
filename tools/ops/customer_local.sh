#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Uso:"
  echo "  bash tools/ops/customer_local.sh release <version> <tenant_slug>"
  echo "  bash tools/ops/customer_local.sh bootstrap <tenant_code> <tenant_slug> <tenant_host>"
  echo "  bash tools/ops/customer_local.sh validate <tenant_slug>"
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
  *)
    usage
    ;;
esac
