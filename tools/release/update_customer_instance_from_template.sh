#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Uso:"
  echo "  update_customer_instance_from_template.sh <customer_instance_slug>"
  exit 1
fi

SLUG="$1"
ROOT="/opt/greenbrain-platform"
TEMPLATE="$ROOT/deploy/customer-local-template"
INSTANCE="$ROOT/deploy/customer-local-instances/$SLUG"

if [ ! -d "$INSTANCE" ]; then
  echo "Istanza non trovata: $INSTANCE"
  exit 1
fi

mkdir -p "$INSTANCE/frontend-dist"
mkdir -p "$INSTANCE/backend-src"
mkdir -p "$INSTANCE/frontend-nginx"
mkdir -p "$INSTANCE/tunnel"
mkdir -p "$INSTANCE/scripts"

rsync -a --delete "$TEMPLATE/frontend-dist/" "$INSTANCE/frontend-dist/"
rsync -a --delete "$TEMPLATE/backend-src/" "$INSTANCE/backend-src/"
rsync -a "$TEMPLATE/frontend-nginx/" "$INSTANCE/frontend-nginx/"
rsync -a "$TEMPLATE/scripts/" "$INSTANCE/scripts/"
rsync -a "$TEMPLATE/tunnel/" "$INSTANCE/tunnel/"
cp "$TEMPLATE/docker-compose.local.yml" "$INSTANCE/docker-compose.local.yml"
cp "$TEMPLATE/README.md" "$INSTANCE/README.md"
cp "$TEMPLATE/VERSION" "$INSTANCE/VERSION"
cp "$TEMPLATE/release-manifest.yml" "$INSTANCE/release-manifest.yml"

echo "Istanza aggiornata dal template: $INSTANCE"
