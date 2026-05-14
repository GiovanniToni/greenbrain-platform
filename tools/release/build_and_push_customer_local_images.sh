#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Uso:"
  echo "  build_and_push_customer_local_images.sh <version> [registry_namespace]"
  echo
  echo "Esempio:"
  echo "  build_and_push_customer_local_images.sh 0.1.106 ghcr.io/giovannitoni"
  exit 1
fi

VERSION="$1"
REGISTRY_NAMESPACE="${2:-ghcr.io/giovannitoni}"

ROOT="/opt/greenbrain-platform"
TEMPLATE="$ROOT/deploy/customer-local-template"

BACKEND_IMAGE="$REGISTRY_NAMESPACE/greenbrain-customer-backend:$VERSION"
ML_WORKER_IMAGE="$REGISTRY_NAMESPACE/greenbrain-customer-ml-worker:$VERSION"

echo "== GreenBrain customer-local image build/push =="
echo "version: $VERSION"
echo "backend: $BACKEND_IMAGE"
echo "ml-worker: $ML_WORKER_IMAGE"
echo

[ -d "$TEMPLATE/base/backend-src" ] || { echo "Missing backend context"; exit 1; }
[ -d "$TEMPLATE/base/apps/ml-worker" ] || { echo "Missing ml-worker context"; exit 1; }

echo "== Build backend image =="
docker build \
  -t "$BACKEND_IMAGE" \
  -t "$REGISTRY_NAMESPACE/greenbrain-customer-backend:latest" \
  "$TEMPLATE/base/backend-src"

echo
echo "== Build ml-worker image =="
docker build \
  -f "$TEMPLATE/base/apps/ml-worker/Dockerfile.local" \
  -t "$ML_WORKER_IMAGE" \
  -t "$REGISTRY_NAMESPACE/greenbrain-customer-ml-worker:latest" \
  "$TEMPLATE/base/apps/ml-worker"

echo
echo "== Local images =="
docker images | grep -E "greenbrain-customer-(backend|ml-worker)|REPOSITORY" || true

if [ "${GREENBRAIN_PUSH_IMAGES:-0}" != "1" ]; then
  echo
  echo "Push skipped."
  echo "To push:"
  echo "  docker login ghcr.io"
  echo "  GREENBRAIN_PUSH_IMAGES=1 $0 $VERSION $REGISTRY_NAMESPACE"
  exit 0
fi

echo
echo "== Push backend image =="
docker push "$BACKEND_IMAGE"
docker push "$REGISTRY_NAMESPACE/greenbrain-customer-backend:latest"

echo
echo "== Push ml-worker image =="
docker push "$ML_WORKER_IMAGE"
docker push "$REGISTRY_NAMESPACE/greenbrain-customer-ml-worker:latest"

echo
echo "IMAGE_PUSH_OK"
