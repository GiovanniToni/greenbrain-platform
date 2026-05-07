# Quick Update Guide

## Update standard
1. creare package
2. applicare update
3. lanciare smoke test

## Comandi

### 1
/opt/greenbrain-platform/client-runtime/scripts/package_client_runtime.sh

### 2
/opt/greenbrain-platform/client-runtime/update.sh /opt/greenbrain-platform/client-runtime/release/current_package

### 3
/opt/greenbrain-platform/apps/ml-worker/tools/run_smoke_runtime.sh
