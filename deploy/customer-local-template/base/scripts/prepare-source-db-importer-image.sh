#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV="$ROOT/overlay/env/customer-local.env"

if [ -f "$ENV" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV"
  set +a
fi

IMAGE_TAG="${GREENBRAIN_IMAGE_TAG:-$(cat "$ROOT/VERSION" 2>/dev/null || echo latest)}"
EXPECTED_IMAGE="ghcr.io/giovannitoni/greenbrain-customer-source-db-importer:${IMAGE_TAG}"
LOCAL_IMAGE="customer-local-template-source-db-importer:latest"

if ! command -v docker >/dev/null 2>&1; then
  echo "SOURCE_DB_IMPORTER_IMAGE_PREP_SKIPPED_NO_DOCKER"
  exit 0
fi

if docker image inspect "$EXPECTED_IMAGE" >/dev/null 2>&1; then
  echo "SOURCE_DB_IMPORTER_IMAGE_READY image=$EXPECTED_IMAGE"
  exit 0
fi

if docker image inspect "$LOCAL_IMAGE" >/dev/null 2>&1; then
  docker tag "$LOCAL_IMAGE" "$EXPECTED_IMAGE"
  echo "SOURCE_DB_IMPORTER_LOCAL_IMAGE_RETAG_OK image=$EXPECTED_IMAGE"
  exit 0
fi

echo "SOURCE_DB_IMPORTER_IMAGE_NOT_FOUND expected=$EXPECTED_IMAGE local=$LOCAL_IMAGE"
exit 0
