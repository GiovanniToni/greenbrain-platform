#!/usr/bin/env bash
set -euo pipefail

cd /opt/greenbrain-platform/client-runtime/etl
source .venv/bin/activate

if grep -q '^SQLSERVER_SERVER=localhost$' .env && \
   grep -q '^SQLSERVER_DB=CLIENT_DB$' .env && \
   grep -q '^SQLSERVER_USER=readonly_user$' .env; then
  echo "[SAFE-STOP] ETL source is still placeholder/demo. Aborting."
  exit 1
fi

if grep -q '^SQLSERVER_PASSWORD=CHANGE_ME$' .env; then
  echo "[SAFE-STOP] ETL password is placeholder. Aborting."
  exit 1
fi

python greenbrain_client_etl.py
