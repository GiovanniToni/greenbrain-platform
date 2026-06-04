# GreenBrain Customer Local — Status and Roadmap 0.1.136

## Release

Release version: 0.1.136

Main goal: make runtime registration idempotent for safe reinstall/retry and fix backend prebuilt compatibility with password seed metadata during local user provisioning.

## Summary

Release 0.1.136 completes the hardening cycle started in 0.1.135.

0.1.135 correctly introduced central runtime registration during local provisioning. That made runtime_bind provisioning tokens move from active to used and bind them to the local installation_id.

During browser/manual retry of the installer, a new case emerged:

    the same local runtime was already installed
    the same provisioning token was already used
    the same installation_id was being registered again
    the cloud backend rejected the token as invalid

The expected behavior is idempotent retry:

    active token + first registration:
        accept and mark token used

    used token + same installation_id:
        accept as safe retry/update

    used token + different installation_id:
        reject as replay/mismatch

0.1.136 implements this idempotent runtime registration behavior.

During validation, a second backend-image compatibility issue was found and fixed: the backend prebuilt image built from apps/backend did not yet support password seed metadata arguments used by provision-local-user.sh. The backend image was updated so local user provisioning accepts and stores password seed metadata correctly.

## Implemented changes

Patch commits:

    e303d87d fix(customer-runtime): allow idempotent runtime registration
    abab3fa5 fix(backend): support password seed metadata during local user provisioning

Version bump commit:

    9de792ab chore(customer-local): bump runtime template to 0.1.136

Files changed:

    apps/backend/app/services/customer_runtime_service.py
    deploy/customer-local-template/base/backend-src/app/services/customer_runtime_service.py
    apps/backend/app/services/customer_auth_user_service.py
    deploy/customer-local-template/VERSION
    deploy/customer-local-template/release-manifest.yml

## Runtime registration idempotency

The runtime register flow now supports:

    token status active:
        consume token and mark used

    token status used with same installation_id:
        accept as idempotent retry

    token status used with different installation_id:
        reject with provisioning_token_installation_mismatch

Validation against dev backend confirmed:

    used token GO2Cw4 + same installation_id:
        HTTP 200
        status=registered

    used token GO2Cw4 + different installation_id:
        runtime_register_failed: provisioning_token_installation_mismatch

This prevents reinstall/update retry from failing with provisioning_token_invalid when the same runtime repeats registration.

## Password seed metadata compatibility

During fresh 0.1.136 validation, local user provisioning initially failed with:

    TypeError: provision_customer_auth_user() got an unexpected keyword argument 'password_version'

Root cause:

    deploy/customer-local-template/base/scripts/provision-local-user.sh passes password seed metadata
    deploy/customer-local-template backend service already supported these fields
    apps/backend backend service did not yet support these fields
    GHCR backend image 0.1.136 was built from apps/backend

The backend service now accepts:

    password_version
    password_changed_at
    password_seed_source
    password_sync_status

and writes password metadata when columns exist:

    password_version
    password_changed_at
    password_change_source
    password_sync_required_at
    password_last_sync_status
    password_last_synced_at
    password_last_sync_attempt_at
    password_last_sync_error

Validated local user provisioning after the fix:

    LOCAL_USER_PROVISION_OK
    password_version=12
    password_change_source=cloud_seed
    password_last_sync_status=synced

## Release artifacts

Release artifacts were built under:

    /opt/greenbrain-platform/releases/customer-local/0.1.136/

Validated files:

    customer-local-0.1.136.tar.gz
    INSTALLA_GREENBRAIN.run
    GreenBrain-Installer.zip
    BUILD-INFO.txt

Build info:

    release_version=0.1.136
    git_commit=9de792ab3c81751247beb29146c4528acea5aaf1

Package validation passed:

    VERSION=0.1.136
    package_version=0.1.136
    wizard_index.html present
    local-sync/password present
    download-bundle endpoint present
    provision-local.sh register markers present
    idempotent register markers present
    PREBUILT_NO_BUILD_OK

## GHCR images

Backend image 0.1.136 was rebuilt because backend source changed.

Validated backend image:

    ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.136

Validated backend digest:

    sha256:68a4f43cdd8e3b67f79e9d72b5cf6253d39fdb25f1bbf8a5e61d5cc9aa48ed11

Backend image contains:

    Register must be idempotent
    provisioning_token_installation_mismatch
    password_version
    password_changed_at
    password_seed_source
    password_sync_status
    password_last_sync_status
    password_last_synced_at
    password_last_sync_attempt_at

ML-worker image 0.1.136 was retagged from 0.1.135.

Validated ml-worker image:

    ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.136

Validated ml-worker digest:

    sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680

## Personalized bundle validation

Customer:

    tenant_code=z
    portal_user_email=z@gmail.com

Cloud login used:

    z@gmail.com / GreenBrain10

Personalized bundle generated after backend image fix:

    customer-local-0.1.136-z-20260604102435.tar.gz
    GreenBrain-Installer-0.1.136-z-20260604102435.zip

Download validation:

    HTTP=200
    x-greenbrain-bundle-version=0.1.136
    x-greenbrain-bundle-filename=GreenBrain-Installer-0.1.136-z-20260604102435.zip
    x-greenbrain-bundle-sha256=d234b96c1ba3f899bda35c3ba54d2093928e0d992b70def9f09085f7318f0875

Bundle inspection:

    VERSION=0.1.136
    package_version=0.1.136
    token_hint=g5PUAo
    register patch markers present
    idempotent register markers present

Token before install:

    token_hint=g5PUAo
    status=active
    used_by_installation_id=NULL
    used_at=NULL

Fresh install path:

    /tmp/gb_0136_personalized_install_z_after_fix_2g64XZ/package/customer-local-template

Install validation:

    PREFLIGHT_LOCAL_INSTALL_OK
    CENTRAL_RUNTIME_REGISTER_OK
    LOCAL_DB_CREDENTIALS_OK
    LOCAL_USER_PROVISION_OK
    INSTALL_RC=0
    installation_id=acf16f9d-a965-4303-beb7-704971738a53
    backend image=ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.136
    ml-worker image=ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.136
    local login z@gmail.com / GreenBrain10 HTTP 200
    doctor completed
    EXTENDED_DOCTOR_OK
    RUN_LOCAL_DAILY_ONCE_OK

Token after install:

    token_hint=g5PUAo
    status=used
    used_by_installation_id=acf16f9d-a965-4303-beb7-704971738a53
    used_at=2026-06-04 10:24:49+00

Retry validation:

    rerun base/scripts/provision-local.sh on same runtime
    CENTRAL_RUNTIME_REGISTER_OK
    token remained used
    used_by_installation_id remained acf16f9d-a965-4303-beb7-704971738a53
    no provisioning_token_invalid

Cloud portal after heartbeat:

    tenant_code=z
    portal_user_email=z@gmail.com
    last_downloaded_release_version=0.1.136
    installed_release_version=0.1.136
    runtime_connection_status=healthy
    latest_installation_id=acf16f9d-a965-4303-beb7-704971738a53
    last_runtime_heartbeat_at=2026-06-04 10:25:10+00

## Final status

0.1.136 is functionally validated.

It fixes:

    reinstall/retry with already-used token on same installation_id
    backend prebuilt compatibility with password seed metadata
    local user provisioning with cloud_seed password metadata

The runtime register lifecycle is now:

    active token -> used token on first install
    used token + same installation_id -> safe retry OK
    used token + different installation_id -> rejected

## Next recommended work

Future hardening can focus on:

    clearer wizard message for update vs fresh install
    explicit retry/update mode label in wizard UI
    automated test coverage for runtime token active/used/replay lifecycle
    automated test coverage for password seed metadata in backend prebuilt image
    cleanup/alignment of old local test installations and old token rows
