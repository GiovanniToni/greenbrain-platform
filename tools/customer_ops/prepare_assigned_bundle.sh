#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Uso:"
  echo "  prepare_assigned_bundle.sh <customer_id> <release_version> <output_dir>"
  exit 1
fi

CUSTOMER_ID="$1"
VERSION="$2"
OUTPUT_DIR="$3"
ROOT="/opt/greenbrain-platform"

bash "$ROOT/tools/customer_runtime/prepare_customer_delivery_bundle.sh" "$VERSION" "$OUTPUT_DIR"

echo
echo "Bundle preparato per customer_id=$CUSTOMER_ID release=$VERSION"
echo "Nota: questo script oggi prepara il bundle file-system; l'aggancio al record customer_ops sarà il passo successivo."
