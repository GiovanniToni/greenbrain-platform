# GreenBrain Customer Local — Status and Roadmap 0.1.134

## Release

Release version: 0.1.134

Main goal: finalize the local top-level password synchronization flow so that after a cloud password change the user can synchronize the local runtime immediately without browser mixed-content blocking.

## Summary

Release 0.1.134 completes the frontend/local runtime password synchronization flow introduced in 0.1.133.

The previous attempt tried to trigger the local runtime directly from the cloud account page:

    https://www.greenbrain.it/account
    -> fetch http://localhost:8008/api/v1/customer-runtime/password-sync/run-local

Browsers blocked this because an HTTPS cloud page cannot call insecure HTTP localhost content directly.

The 0.1.134 solution avoids mixed content by opening a local top-level page served by the customer-local frontend:

    http://localhost:8088/local-sync/password

That local page then calls the local runtime through the local nginx proxy:

    POST /api/v1/customer-runtime/password-sync/run-local

This keeps the call entirely inside the local origin and avoids HTTPS-to-HTTP mixed-content blocking.

## Implemented changes

Frontend source changes:

    apps/frontend/src/App.tsx
    apps/frontend/src/pages/CustomerPortalDashboard.tsx
    apps/frontend/src/pages/LocalPasswordSync.tsx

Template frontend dist updated:

    deploy/customer-local-template/base/frontend-dist

Important correction before finalizing:

    deploy/customer-local-template/base/frontend-dist/wizard_index.html

was restored after build-copy validation because it is still used by the local installer wizard:

    deploy/customer-local-template/base/apps/local-installer-wizard/wizard.py

## Validated behavior

### Local top-level sync page

Validated local page:

    http://localhost:8088/local-sync/password

Validated asset markers:

    local-sync/password
    Sincronizzazione password
    Sincronizza GreenBrain locale ora
    /api/v1/customer-runtime/password-sync/run-local

Validated local API call through frontend proxy:

    POST http://localhost:8088/api/v1/customer-runtime/password-sync/run-local

Expected result when already aligned:

    {"status":"no_pending"}

Expected result when a cloud password change is pending:

    {"status":"synced"}

## End-to-end password sync validation

Validated scenario:

    cloud password GreenBrain8 -> GreenBrain9
    cloud password_version advanced to 11
    cloud status became pending
    local still accepted GreenBrain8 before sync
    local rejected GreenBrain9 before sync
    run-local through localhost:8088 returned synced
    local accepted GreenBrain9 after sync
    local rejected GreenBrain8 after sync
    cloud ACK became synced
    second run-local returned no_pending

This confirms that the architecture avoids mixed-content blocking and synchronizes the local password immediately when the runtime is available.

## GHCR images

No backend or ml-worker source changes were made between 0.1.133 and 0.1.134.

Therefore the images were safely retagged from 0.1.133 to 0.1.134.

Validated pushed images:

    ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.134
    ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.134

Validated digests:

    backend:   sha256:7f0fca93cbd49310e5c1114a47075a3453a7690f1de96f152ca143cdb2e40d23
    ml-worker: sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680

## Generic release validation

Generic release artifacts were built under:

    /opt/greenbrain-platform/releases/customer-local/0.1.134/

Expected files validated:

    customer-local-0.1.134.tar.gz
    INSTALLA_GREENBRAIN.run
    GreenBrain-Installer.zip
    BUILD-INFO.txt

Generic fresh install validated:

    VERSION=0.1.134
    backend image=ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.134
    ml-worker image=ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.134
    backend health OK
    frontend OK
    local-sync/password OK
    doctor completed
    EXTENDED_DOCTOR_OK
    RUN_LOCAL_DAILY_ONCE_OK
    heartbeat healthy

## Personalized bundle validation

Customer:

    tenant_code=z
    portal_user_email=z@gmail.com

Personalized bundle generated:

    customer-local-0.1.134-z-20260604081358.tar.gz
    GreenBrain-Installer-0.1.134-z-20260604081358.zip

Bundle validation:

    VERSION=0.1.134
    package_version=0.1.134
    TENANT_CODE=z
    TOKEN_HINT=CjKGxo
    wizard_index.html present
    local-sync/password present
    download-bundle endpoint present

Fresh install from personalized bundle succeeded:

    INSTALL_RC=0
    installation_id=4b12e4a5-1b74-4857-9083-a0818d23863e
    backend image=ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.134
    ml-worker image=ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.134
    LOCAL_USER_PROVISION_OK
    password_version=11
    password_change_source=cloud_seed
    password_last_sync_status=synced
    local login z@gmail.com / GreenBrain9 HTTP 200
    run-local returned no_pending
    doctor completed
    EXTENDED_DOCTOR_OK
    RUN_LOCAL_DAILY_ONCE_OK

Cloud portal after heartbeat:

    last_downloaded_release_version=0.1.134
    installed_release_version=0.1.134
    runtime_connection_status=healthy
    latest_installation_id=4b12e4a5-1b74-4857-9083-a0818d23863e
    last_runtime_heartbeat_at=2026-06-04 08:18:38+00

## Known non-blocking issue for 0.1.135

During final validation, the provisioning token used by the personalized bundle remained:

    token_hint=CjKGxo
    status=active
    used_by_installation_id=NULL
    used_at=NULL

The backend already supports marking a runtime token as used through:

    POST /api/v1/customer-runtime/register

and service/repository code includes:

    mark_runtime_token_used(...)
    status=used
    used_at=...
    used_by_installation_id=...

However, the current installer path does not call the central runtime register endpoint. The current local provisioning script only validates required env values and prints Provisioning OK.

Therefore this is classified as a non-blocking hardening item for 0.1.135:

    0.1.135 target:
    make provision-local.sh call /api/v1/customer-runtime/register once after INSTALLATION_ID and PROVISIONING_TOKEN are available, then validate that token status becomes used.

This should be implemented carefully and tested separately, without destabilizing the already validated 0.1.134 release.

## Final status

0.1.134 is functionally validated and ready to tag/push.
