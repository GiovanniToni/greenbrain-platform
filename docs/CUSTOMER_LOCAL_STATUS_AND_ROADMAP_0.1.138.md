# GreenBrain Customer Local — Status and Roadmap 0.1.138

## Release

Release version: 0.1.138

Main goal: finalize the immediate local password synchronization flow by fixing the local frontend nginx proxy and hardening the run-local endpoint when cloud connectivity is temporarily unavailable.

## Summary

Release 0.1.138 closes the password synchronization flow introduced and hardened across 0.1.133 through 0.1.137.

0.1.137 correctly added the local password sync page and backend route:

    /local-sync/password
    /api/v1/customer-runtime/password-sync/run-local

The backend image 0.1.137 exposed the route correctly, and direct backend calls to:

    http://localhost:8008/api/v1/customer-runtime/password-sync/run-local

returned HTTP 200.

However, the browser button still failed through the local frontend proxy:

    http://localhost:8088/api/v1/customer-runtime/password-sync/run-local

The root cause was the nginx proxy target in the local frontend container. It was using:

    proxy_pass http://host.docker.internal:8008;

On macOS this resolved to an upstream that was not reliable for the fresh runtime route and returned 404 for run-local, while the correct Docker service backend exposed the route.

0.1.138 changes the local frontend nginx proxy to use the Docker service directly:

    proxy_pass http://backend:8000;

This keeps all local API calls under:

    http://localhost:8088/api/

and makes the local password sync button work consistently.

The release also hardens the run-local endpoint so temporary cloud network errors do not return an unhandled 500 traceback. Instead, the route returns a controlled JSON response:

    status=pending_failed
    pending_http_status=0
    detail=cloud_unreachable

## Implemented changes

Patch commit:

    765d3367 fix(customer-local): proxy local api to backend service

Version bump commit:

    4eeb8494 chore(customer-local): bump runtime template to 0.1.138

Files changed:

    deploy/customer-local-template/overlay/frontend-nginx/default.conf
    deploy/customer-local-template/frontend-nginx/default.conf
    apps/backend/app/api/v1/customer_runtime.py
    deploy/customer-local-template/base/backend-src/app/api/v1/customer_runtime.py
    deploy/customer-local-template/VERSION
    deploy/customer-local-template/release-manifest.yml

## Nginx local proxy fix

Previous proxy target:

    proxy_pass http://host.docker.internal:8008;

New proxy target:

    proxy_pass http://backend:8000;

Validated behavior:

    POST http://localhost:8088/api/v1/customer-runtime/password-sync/run-local
    HTTP 200

This confirms that the browser-accessible local frontend can now call the backend route through nginx.

## Run-local network hardening

The local run-local endpoint now catches cloud pending lookup failures and returns a controlled JSON error instead of raising an unhandled exception.

Response on cloud connectivity failure:

    {
      "status": "pending_failed",
      "pending_http_status": 0,
      "detail": "cloud_unreachable",
      "error": "..."
    }

This avoids confusing browser errors if the customer's local runtime cannot temporarily reach the cloud.

## Browser validation on macOS

Real macOS browser validation succeeded after hotfixing nginx locally from:

    host.docker.internal:8008

to:

    backend:8000

Customer:

    tenant_code=z
    email=z@gmail.com
    installation_id=c1c1eaa6-2a0b-4a1a-8b36-5c1af78fce68

Password change tested:

    zzzzzzzz5 -> zzzzzzzz6

Browser local sync result:

    status=synced
    tenant_code=z
    email=z@gmail.com
    password_version=18
    password_last_sync_status=synced
    ack_http_status=200
    ack_status=password_sync_synced

This confirmed the user-facing flow:

    change password in cloud account
    click Sincronizza GreenBrain locale ora
    local password sync completes successfully

## Release artifacts

Release artifacts were built under:

    /opt/greenbrain-platform/releases/customer-local/0.1.138/

Validated files:

    customer-local-0.1.138.tar.gz
    INSTALLA_GREENBRAIN.run
    GreenBrain-Installer.zip
    BUILD-INFO.txt

Build info:

    release_version=0.1.138
    git_commit=4eeb84945b3a6e3118bc9811ce09c084b93a993d

Safe bundle validation result:

    SAFE_RELEASE_BUNDLE_VALIDATION_OK

Validated bundle contents:

    VERSION=0.1.138
    package_version=0.1.138
    proxy_pass http://backend:8000
    no old proxy_pass http://host.docker.internal:8008
    /api/v1/customer-runtime/password-sync/run-local
    cloud_unreachable
    pending_http_status=0
    apply_cloud_password_sync
    local-sync/password
    docker-compose.prebuilt.yml has no build sections

## GHCR images

Backend image:

    ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.138

Backend digest:

    sha256:5393a58cda52e2562340544f15fe64bd04ad9c76b2b0fe6aa6e957d7540a0655

ML-worker image:

    ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.138

ML-worker digest:

    sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680

GHCR validation result:

    GHCR_0138_BACKEND_AND_ML_WORKER_VALIDATION_OK

Backend image contains:

    /password-sync/run-local
    cloud_unreachable
    pending_http_status=0
    pending_failed
    apply_cloud_password_sync
    ensure_password_sync_schema
    password_synced_from_cloud

## Fresh personalized install validation

Customer:

    tenant_code=z
    portal_user_email=z@gmail.com

Cloud login password used for validation:

    zzzzzzzz6

Personalized bundle downloaded:

    GreenBrain-Installer-0.1.138-z-20260604122908.zip

SHA256:

    3a3e614bfba007e13cc2ff46115b3fcb295d6415087fb12d26101335a4b8280e

Token hint:

    8M9nQo

Fresh install path:

    /tmp/gb_0138_personalized_install_z_EwtoDh/package/customer-local-template

Fresh install validation:

    INSTALL_RC=0
    CENTRAL_RUNTIME_REGISTER_OK
    LOCAL_USER_PROVISION_OK
    installation_id=c11930e4-d002-4ab4-a3cd-604a4f65cede
    backend image=ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.138
    ml-worker image=ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.138
    nginx config proxy_pass http://backend:8000
    OpenAPI includes /api/v1/customer-runtime/password-sync/run-local
    frontend proxy run-local HTTP 200
    direct backend run-local HTTP 200
    local login z@gmail.com / zzzzzzzz6 HTTP 200
    EXTENDED_DOCTOR_OK
    RUN_LOCAL_DAILY_ONCE_OK

Token state after install:

    token_hint=8M9nQo
    status=used
    used_by_installation_id=c11930e4-d002-4ab4-a3cd-604a4f65cede

Cloud portal state after heartbeat:

    last_downloaded_release_version=0.1.138
    installed_release_version=0.1.138
    runtime_connection_status=healthy
    latest_installation_id=c11930e4-d002-4ab4-a3cd-604a4f65cede
    last_runtime_heartbeat_at=2026-06-04 12:29:42+00

Validation result:

    FRESH_PERSONALIZED_INSTALL_0138_VALIDATION_OK

## Final status

0.1.138 is functionally validated.

It fixes:

    browser Not Found on immediate local password sync
    incorrect local frontend nginx upstream on macOS
    unhandled 500 errors when cloud pending lookup is temporarily unreachable

The immediate password sync flow is now:

    password changed in cloud account
    user is sent to local sync page
    local page calls localhost:8088/api/v1/customer-runtime/password-sync/run-local
    nginx proxies to backend:8000
    backend fetches pending cloud password action
    local DB password hash is updated
    cloud receives ack
    local page shows synced

## Next recommended work

Future work can focus on:

    automated end-to-end browser test for password sync
    clearer UI message when no pending password sync exists
    optional retry/backoff on cloud_unreachable
    cleanup of old test provisioning tokens and old local test installations
