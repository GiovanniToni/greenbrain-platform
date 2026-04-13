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

mkdir -p "$INSTANCE/base/backend-src"
mkdir -p "$INSTANCE/base/frontend-dist"
mkdir -p "$INSTANCE/base/scripts"
mkdir -p "$INSTANCE/base/systemd"
mkdir -p "$INSTANCE/base/desktop"
mkdir -p "$INSTANCE/base/tunnel"
mkdir -p "$INSTANCE/overlay/env"
mkdir -p "$INSTANCE/overlay/frontend-nginx"
mkdir -p "$INSTANCE/overlay/tunnel/cloudflared"
mkdir -p "$INSTANCE/overlay/meta"

rsync -a --delete "$TEMPLATE/base/backend-src/" "$INSTANCE/base/backend-src/"
rsync -a --delete "$TEMPLATE/base/frontend-dist/" "$INSTANCE/base/frontend-dist/"
rsync -a --delete "$TEMPLATE/base/scripts/" "$INSTANCE/base/scripts/"
rsync -a "$TEMPLATE/base/systemd/" "$INSTANCE/base/systemd/" 2>/dev/null || true
rsync -a "$TEMPLATE/base/desktop/" "$INSTANCE/base/desktop/" 2>/dev/null || true
rsync -a "$TEMPLATE/base/tunnel/" "$INSTANCE/base/tunnel/" 2>/dev/null || true

# overlay: copiamo solo file esempio / non sensibili
if [ -f "$TEMPLATE/overlay/frontend-nginx/default.conf" ]; then
  cp "$TEMPLATE/overlay/frontend-nginx/default.conf" \
     "$INSTANCE/overlay/frontend-nginx/default.conf.template"
fi

if [ -f "$TEMPLATE/overlay/tunnel/cloudflared/config.yml.example" ]; then
  cp "$TEMPLATE/overlay/tunnel/cloudflared/config.yml.example" \
     "$INSTANCE/overlay/tunnel/cloudflared/config.yml.example"
fi

if [ -f "$TEMPLATE/overlay/tunnel/cloudflared/cloudflared.env.example" ]; then
  cp "$TEMPLATE/overlay/tunnel/cloudflared/cloudflared.env.example" \
     "$INSTANCE/overlay/tunnel/cloudflared/cloudflared.env.example"
fi

cp "$TEMPLATE/docker-compose.local.yml" "$INSTANCE/docker-compose.local.yml"
cp "$TEMPLATE/tunnel/docker-compose.tunnel.yml" "$INSTANCE/tunnel/docker-compose.tunnel.yml"
cp "$TEMPLATE/README.md" "$INSTANCE/README.md"
cp "$TEMPLATE/VERSION" "$INSTANCE/VERSION"
cp "$TEMPLATE/release-manifest.yml" "$INSTANCE/release-manifest.yml"
cp "$TEMPLATE/base-overlay-model.md" "$INSTANCE/base-overlay-model.md"

echo "Istanza aggiornata dal template base/overlay: $INSTANCE"
