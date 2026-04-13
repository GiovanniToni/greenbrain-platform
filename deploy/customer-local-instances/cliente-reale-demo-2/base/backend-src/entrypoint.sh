#!/bin/sh
# GreenBrain Backend — production entrypoint
# Expands env vars at container start so secrets are never baked into the image.
set -e

exec uvicorn app.main:app \
    --host 0.0.0.0 \
    --port "${PORT:-8000}" \
    --workers "${WORKERS:-2}" \
    --log-level "${LOG_LEVEL:-info}" \
    --proxy-headers \
    --forwarded-allow-ips "*"
