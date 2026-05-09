#!/usr/bin/env bash
set -euo pipefail

echo "== GreenBrain Local Doctor =="

curl -fsS http://127.0.0.1:8008/health >/dev/null
echo "backend: OK"

curl -fsS http://127.0.0.1:8088 >/dev/null
echo "frontend: OK"

echo "doctor completed"
