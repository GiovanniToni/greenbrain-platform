#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 0.1.138"
  exit 2
fi

BACKEND_IMAGE="ghcr.io/giovannitoni/greenbrain-customer-backend:${VERSION}"
ML_WORKER_IMAGE="ghcr.io/giovannitoni/greenbrain-customer-ml-worker:${VERSION}"

section() {
  echo
  echo "===== $1 ====="
}

grep_required_in_image() {
  local image="$1"
  local file="$2"
  local pattern="$3"

  docker run --rm --entrypoint sh "$image" -lc \
    "grep -nE '$pattern' '$file'" \
    || {
      echo "PATTERN_NOT_FOUND_IN_IMAGE image=$image file=$file pattern=$pattern"
      exit 1
    }
}

section "PULL BACKEND IMAGE"
docker pull "$BACKEND_IMAGE"

section "PULL ML-WORKER IMAGE"
docker pull "$ML_WORKER_IMAGE"

section "IMAGE DIGESTS"
docker image inspect "$BACKEND_IMAGE" \
  --format 'BACKEND_IMAGE_ID={{.Id}} RepoDigests={{json .RepoDigests}}'

docker image inspect "$ML_WORKER_IMAGE" \
  --format 'ML_WORKER_IMAGE_ID={{.Id}} RepoDigests={{json .RepoDigests}}'

section "VALIDATE BACKEND IMAGE ROUTE MARKERS"
grep_required_in_image "$BACKEND_IMAGE" "/app/app/api/v1/customer_runtime.py" \
  '@router.post\("/password-sync/run-local"\)|def run_local_password_sync_route|cloud_unreachable|pending_http_status.: 0|pending_failed|apply_cloud_password_sync'

section "VALIDATE BACKEND IMAGE DB MARKERS"
grep_required_in_image "$BACKEND_IMAGE" "/app/app/db/users.py" \
  'def ensure_password_sync_schema|def apply_cloud_password_sync|password_synced_from_cloud|local_user_not_found_or_not_updated|password_version_missing'

section "VALIDATE BACKEND IMAGE RUNTIME REGISTER MARKERS"
grep_required_in_image "$BACKEND_IMAGE" "/app/app/services/customer_runtime_service.py" \
  'Register must be idempotent|get_runtime_token_by_hash|provisioning_token_installation_mismatch|if status == "used"|if status != "active"'

section "VALIDATE BACKEND IMAGE PASSWORD SEED MARKERS"
grep_required_in_image "$BACKEND_IMAGE" "/app/app/services/customer_auth_user_service.py" \
  'password_version|password_changed_at|password_seed_source|password_sync_status|password_last_sync_status|password_last_synced_at|password_last_sync_attempt_at'

section "VALIDATE ML-WORKER IMAGE BASIC SMOKE"
docker run --rm --entrypoint sh "$ML_WORKER_IMAGE" -lc '
python - <<PY
import sys
print("python", sys.version.split()[0])
print("ML_WORKER_IMAGE_BASIC_SMOKE_OK")
PY
'

section "FINAL RESULT"
echo "CUSTOMER_LOCAL_IMAGES_VALIDATION_OK version=${VERSION}"
