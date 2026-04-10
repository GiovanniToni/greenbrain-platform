#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Uso:"
  echo "  create_customer_local_package.sh <tenant_code> <customer_slug>"
  exit 1
fi

TENANT_CODE="$1"
CUSTOMER_SLUG="$2"

ROOT="/opt/greenbrain-platform"
TEMPLATE_DIR="$ROOT/deploy/customer-local-template"
TARGET_DIR="$ROOT/deploy/customer-local-instances/$CUSTOMER_SLUG"

if [ -d "$TARGET_DIR" ]; then
  echo "Esiste già: $TARGET_DIR"
  exit 1
fi

mkdir -p "$ROOT/deploy/customer-local-instances"
cp -R "$TEMPLATE_DIR" "$TARGET_DIR"

ENV_FILE="$TARGET_DIR/env/customer-local.env.example"

sed -i "s/cliente_reale/$TENANT_CODE/g" "$ENV_FILE"
sed -i "s/Cliente Reale/$CUSTOMER_SLUG/g" "$ENV_FILE"
sed -i "s/cliente-reale.greenbrain.it/$TENANT_CODE.greenbrain.it/g" "$ENV_FILE"
sed -i "s/greenbrain_cliente_reale/greenbrain_${TENANT_CODE}/g" "$ENV_FILE"
sed -i "s/CHANGE_ME_DB_PASSWORD/${TENANT_CODE}_DB_PASSWORD/g" "$ENV_FILE"
sed -i "s/CHANGE_ME_LOCAL_JWT_SECRET/${TENANT_CODE}_LOCAL_JWT_SECRET/g" "$ENV_FILE"
sed -i "s/CHANGE_ME_TUNNEL_TOKEN/${TENANT_CODE}_TUNNEL_TOKEN/g" "$ENV_FILE"

mv "$ENV_FILE" "$TARGET_DIR/env/customer-local.env"

echo "Pacchetto creato in: $TARGET_DIR"
echo
echo "Prossimi passi:"
echo "1) apri $TARGET_DIR/env/customer-local.env"
echo "2) sostituisci password e secret placeholder"
echo "3) build frontend se serve"
echo "4) avvia con: bash $TARGET_DIR/scripts/start-local.sh"
