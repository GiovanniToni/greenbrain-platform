#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNTIME_ENV="$ROOT/overlay/provisioning/local-runtime.env"
REPORT_JSON="$ROOT/overlay/logs/source-db/technical_check_latest.json"
LOG_DIR="$ROOT/overlay/logs/source-db"

mkdir -p "$LOG_DIR"

TS="$(date -u +%Y%m%d_%H%M%S)"
LOG="$LOG_DIR/technical_report_upload_${TS}.log"
LATEST="$LOG_DIR/technical_report_upload_latest.log"

echo "== GreenBrain Source DB Technical Report Upload ==" | tee "$LOG"

if [ ! -f "$RUNTIME_ENV" ]; then
  echo "SOURCE_DB_TECHNICAL_UPLOAD_SKIPPED missing_runtime_env:$RUNTIME_ENV" | tee -a "$LOG"
  ln -sfn "$(basename "$LOG")" "$LATEST"
  exit 3
fi

if [ ! -f "$REPORT_JSON" ]; then
  echo "SOURCE_DB_TECHNICAL_UPLOAD_SKIPPED missing_report:$REPORT_JSON" | tee -a "$LOG"
  ln -sfn "$(basename "$LOG")" "$LATEST"
  exit 4
fi

set -a
# shellcheck disable=SC1090
. "$RUNTIME_ENV"
set +a

TENANT_CODE="${TENANT_CODE:-}"
INSTALLATION_ID="${INSTALLATION_ID:-}"
PROVISIONING_TOKEN="${PROVISIONING_TOKEN:-}"

if [ -z "$TENANT_CODE" ]; then
  echo "SOURCE_DB_TECHNICAL_UPLOAD_FAILED missing_TENANT_CODE" | tee -a "$LOG"
  ln -sfn "$(basename "$LOG")" "$LATEST"
  exit 5
fi

if [ -z "$INSTALLATION_ID" ]; then
  echo "SOURCE_DB_TECHNICAL_UPLOAD_FAILED missing_INSTALLATION_ID" | tee -a "$LOG"
  ln -sfn "$(basename "$LOG")" "$LATEST"
  exit 6
fi

if [ -z "$PROVISIONING_TOKEN" ]; then
  echo "SOURCE_DB_TECHNICAL_UPLOAD_FAILED missing_PROVISIONING_TOKEN" | tee -a "$LOG"
  ln -sfn "$(basename "$LOG")" "$LATEST"
  exit 7
fi

CENTRAL_BASE="${CENTRAL_AUTH_URL:-}"
if [ -z "$CENTRAL_BASE" ]; then
  HEARTBEAT_URL="${HEARTBEAT_URL:-}"
  SUFFIX="/api/v1/customer-runtime/heartbeat"
  if [ -n "$HEARTBEAT_URL" ] && [ "${HEARTBEAT_URL%$SUFFIX}" != "$HEARTBEAT_URL" ]; then
    CENTRAL_BASE="${HEARTBEAT_URL%$SUFFIX}"
  else
    CENTRAL_BASE="https://www.greenbrain.it"
  fi
fi
CENTRAL_BASE="${CENTRAL_BASE%/}"

UPLOAD_URL="$CENTRAL_BASE/api/v1/customer-runtime/source-db/technical-check"

python3 - "$REPORT_JSON" "$TENANT_CODE" "$INSTALLATION_ID" "$UPLOAD_URL" "$PROVISIONING_TOKEN" <<'PY' 2>&1 | tee -a "$LOG"
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

report_path = Path(sys.argv[1])
tenant_code = sys.argv[2]
installation_id = sys.argv[3]
upload_url = sys.argv[4]
token = sys.argv[5]

report = json.loads(report_path.read_text(encoding="utf-8"))

status = str(report.get("status") or "").strip()
if status not in {"technical_test_ok", "technical_test_failed"}:
    raise SystemExit(f"SOURCE_DB_TECHNICAL_UPLOAD_FAILED invalid_report_status:{status}")

errors = report.get("errors") or []
error = None
if status == "technical_test_failed":
    if isinstance(errors, list) and errors:
        error = "; ".join(str(x) for x in errors[:5])
    else:
        error = "technical_test_failed"

payload = {
    "tenant_code": tenant_code,
    "installation_id": installation_id,
    "status": status,
    "report": json.dumps(report, ensure_ascii=False, default=str)[:20000],
    "result": report,
    "error": error,
}

data = json.dumps(payload, ensure_ascii=False, default=str).encode("utf-8")
headers = {
    "Content-Type": "application/json",
    "Accept": "application/json",
    "Authorization": "Bearer " + token,
    "User-Agent": "GreenBrainCustomerLocal source-db-technical-uploader",
}

req = urllib.request.Request(upload_url, data=data, headers=headers, method="POST")

try:
    with urllib.request.urlopen(req, timeout=20) as resp:
        body = resp.read().decode("utf-8", "replace")
        http_status = int(resp.status)
except urllib.error.HTTPError as exc:
    body = exc.read().decode("utf-8", "replace")
    http_status = int(exc.code)

print("UPLOAD_URL=" + upload_url)
print("HTTP_STATUS=" + str(http_status))
print(body)

if http_status != 200:
    raise SystemExit("SOURCE_DB_TECHNICAL_UPLOAD_FAILED http_status=" + str(http_status))

parsed = json.loads(body or "{}")
if parsed.get("status") != "source_db_technical_test_recorded":
    raise SystemExit("SOURCE_DB_TECHNICAL_UPLOAD_FAILED unexpected_response_status")

if "source_db_integration" in parsed:
    raise SystemExit("SOURCE_DB_TECHNICAL_UPLOAD_FAILED raw_integration_returned")

print("SOURCE_DB_TECHNICAL_UPLOAD_OK")
PY

RC="${PIPESTATUS[0]}"
ln -sfn "$(basename "$LOG")" "$LATEST"

if [ "$RC" -ne 0 ]; then
  echo "SOURCE_DB_TECHNICAL_UPLOAD_FAILED rc=$RC" | tee -a "$LOG"
  exit "$RC"
fi

echo "SOURCE_DB_TECHNICAL_REPORT_UPLOAD_OK" | tee -a "$LOG"
