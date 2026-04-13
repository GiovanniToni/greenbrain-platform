#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Uso:"
  echo "  create_customer_local_instance.sh <tenant_code> <tenant_slug> <tenant_host>"
  exit 1
fi

TENANT_CODE="$1"
TENANT_SLUG="$2"
TENANT_HOST="$3"

ROOT="/opt/greenbrain-platform"
TEMPLATE="$ROOT/deploy/customer-local-template"
INSTANCE="$ROOT/deploy/customer-local-instances/$TENANT_SLUG"

if [ ! -d "$TEMPLATE" ]; then
  echo "Template non trovato: $TEMPLATE"
  exit 1
fi

if [ -d "$INSTANCE" ]; then
  echo "Istanza già esistente: $INSTANCE"
  exit 1
fi

mkdir -p "$INSTANCE"

mkdir -p "$INSTANCE/base/backend-src"
mkdir -p "$INSTANCE/base/frontend-dist"
mkdir -p "$INSTANCE/base/scripts"
mkdir -p "$INSTANCE/base/systemd"
mkdir -p "$INSTANCE/base/desktop"
mkdir -p "$INSTANCE/base/tunnel"
mkdir -p "$INSTANCE/tunnel"

mkdir -p "$INSTANCE/overlay/env"
mkdir -p "$INSTANCE/overlay/frontend-nginx"
mkdir -p "$INSTANCE/overlay/tunnel/cloudflared"
mkdir -p "$INSTANCE/overlay/meta"

echo "== Copia base dal template =="
rsync -a --delete "$TEMPLATE/base/backend-src/" "$INSTANCE/base/backend-src/"
rsync -a --delete "$TEMPLATE/base/frontend-dist/" "$INSTANCE/base/frontend-dist/"
rsync -a --delete "$TEMPLATE/base/scripts/" "$INSTANCE/base/scripts/"
rsync -a "$TEMPLATE/base/systemd/" "$INSTANCE/base/systemd/" 2>/dev/null || true
rsync -a "$TEMPLATE/base/desktop/" "$INSTANCE/base/desktop/" 2>/dev/null || true
rsync -a "$TEMPLATE/base/tunnel/" "$INSTANCE/base/tunnel/" 2>/dev/null || true

echo "== Copia file root gestiti dal template =="
cp "$TEMPLATE/docker-compose.local.yml" "$INSTANCE/docker-compose.local.yml"
cp "$TEMPLATE/tunnel/docker-compose.tunnel.yml" "$INSTANCE/tunnel/docker-compose.tunnel.yml"
cp "$TEMPLATE/README.md" "$INSTANCE/README.md"
cp "$TEMPLATE/VERSION" "$INSTANCE/VERSION"
cp "$TEMPLATE/release-manifest.yml" "$INSTANCE/release-manifest.yml"
cp "$TEMPLATE/base-overlay-model.md" "$INSTANCE/base-overlay-model.md"
cp "$TEMPLATE/base/base-manifest.yml" "$INSTANCE/base/base-manifest.yml"
cp "$TEMPLATE/overlay/meta/overlay-manifest.yml" "$INSTANCE/overlay/meta/overlay-manifest.yml"

echo "== Genera overlay env =="
cp "$TEMPLATE/env/customer-local.env.example" "$INSTANCE/overlay/env/customer-local.env"

python3 - <<PY
from pathlib import Path

p = Path("$INSTANCE/overlay/env/customer-local.env")
s = p.read_text()

repl = {
    "TENANT_CODE=cliente_reale": "TENANT_CODE=%s" % "$TENANT_CODE",
    "TENANT_NAME=Cliente Reale": "TENANT_NAME=%s" % "$TENANT_SLUG",
    "TENANT_HOST=cliente-reale.greenbrain.it": "TENANT_HOST=%s" % "$TENANT_HOST",
    "CENTRAL_TENANT_CODE=cliente_reale": "CENTRAL_TENANT_CODE=%s" % "$TENANT_CODE",
    "TUNNEL_PUBLIC_HOST=cliente-reale.greenbrain.it": "TUNNEL_PUBLIC_HOST=%s" % "$TENANT_HOST",
    "POSTGRES_DB=greenbrain_cliente_reale": "POSTGRES_DB=greenbrain_%s" % "$TENANT_CODE".replace("-", "_"),
    "POSTGRES_USER=greenbrain_cliente_reale": "POSTGRES_USER=greenbrain_%s" % "$TENANT_CODE".replace("-", "_"),
    "DATABASE_URL=postgresql://greenbrain_cliente_reale:CHANGE_ME_DB_PASSWORD@postgres:5432/greenbrain_cliente_reale":
        "DATABASE_URL=postgresql://greenbrain_%s:CHANGE_ME_DB_PASSWORD@postgres:5432/greenbrain_%s" % (
            "$TENANT_CODE".replace("-", "_"),
            "$TENANT_CODE".replace("-", "_"),
        ),
}

for old, new in repl.items():
    s = s.replace(old, new)

s = s.replace("CHANGE_ME_DB_PASSWORD", f"{'$TENANT_CODE'}_DB_PASSWORD")
s = s.replace("CHANGE_ME_LOCAL_JWT_SECRET", f"{'$TENANT_CODE'}_LOCAL_JWT_SECRET")
s = s.replace("CHANGE_ME_TUNNEL_TOKEN", f"{'$TENANT_CODE'}_TUNNEL_TOKEN")

s = s.replace(f"{'$TENANT_CODE'}", "$TENANT_CODE")
p.write_text(s)
print("UPDATED", p)
PY

echo "== Genera overlay frontend nginx =="
cp "$TEMPLATE/overlay/frontend-nginx/default.conf" \
   "$INSTANCE/overlay/frontend-nginx/default.conf"

echo "== Genera overlay tunnel =="
cp "$TEMPLATE/overlay/tunnel/cloudflared/config.yml.example" \
   "$INSTANCE/overlay/tunnel/cloudflared/config.yml"

cp "$TEMPLATE/overlay/tunnel/cloudflared/cloudflared.env.example" \
   "$INSTANCE/overlay/tunnel/cloudflared/cloudflared.env"

python3 - <<PY
from pathlib import Path

files = [
    Path("$INSTANCE/overlay/tunnel/cloudflared/config.yml"),
    Path("$INSTANCE/overlay/tunnel/cloudflared/cloudflared.env"),
]

for p in files:
    s = p.read_text()
    s = s.replace("cliente-reale.greenbrain.it", "$TENANT_HOST")
    s = s.replace("CHANGE_ME_TUNNEL_ID", "REPLACE_WITH_REAL_TUNNEL_UUID")
    p.write_text(s)
    print("UPDATED", p)
PY

echo "== Verifica coerenza bootstrap =="
grep -q "TENANT_HOST=$TENANT_HOST" "$INSTANCE/overlay/env/customer-local.env"
grep -q "TUNNEL_PUBLIC_HOST=$TENANT_HOST" "$INSTANCE/overlay/env/customer-local.env"
grep -q "$TENANT_HOST" "$INSTANCE/overlay/tunnel/cloudflared/config.yml"
grep -q "$TENANT_HOST" "$INSTANCE/overlay/tunnel/cloudflared/cloudflared.env"

docker compose   --env-file "$INSTANCE/overlay/env/customer-local.env"   -f "$INSTANCE/docker-compose.local.yml"   config >/dev/null

docker compose   -f "$INSTANCE/tunnel/docker-compose.tunnel.yml"   config >/dev/null

echo "== Istanza bootstrap completata =="
echo "Path: $INSTANCE"
echo
echo "Prossimi passi:"
echo "1) compila overlay/env/customer-local.env"
echo "2) inserisci config tunnel reali in overlay/tunnel/cloudflared/"
echo "3) registra tenant centrale"
echo "4) avvia docker compose locale"
