#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-deploy/env/dev-cloud.env}"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: env file not found: $ENV_FILE" >&2
  exit 1
fi

if grep -q "dev_postgres" "$ENV_FILE"; then
  echo "ERROR: $ENV_FILE points to dev_postgres. Dev cloud must use Supabase cloud." >&2
  exit 1
fi

if ! grep -q "aws-1-eu-west-1.pooler.supabase.com" "$ENV_FILE"; then
  echo "ERROR: $ENV_FILE does not point to Supabase pooler host." >&2
  exit 1
fi

if ! grep -q "^POSTGRES_DB=postgres$" "$ENV_FILE"; then
  echo "ERROR: $ENV_FILE must use POSTGRES_DB=postgres for Supabase." >&2
  exit 1
fi

if ! grep -q "^POSTGRES_SSLMODE=require$" "$ENV_FILE"; then
  echo "ERROR: $ENV_FILE must use POSTGRES_SSLMODE=require." >&2
  exit 1
fi

echo "OK: dev cloud env points to Supabase cloud"
