#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

ENV_FILE="$ROOT/overlay/provisioning/local-runtime.env"
TARGET_ENV="$ROOT/overlay/env/customer-local.env"

mkdir -p "$(dirname "$TARGET_ENV")"

cp "$ENV_FILE" "$TARGET_ENV"

echo "Provisioning env generated:"
echo "  $TARGET_ENV"
