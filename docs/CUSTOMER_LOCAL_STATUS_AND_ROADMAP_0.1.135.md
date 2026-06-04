# GreenBrain Customer Local — Status and Roadmap 0.1.135

## Release

Release version: 0.1.135

Main goal: complete runtime provisioning-token consumption during local installation.

## Summary

Release 0.1.135 fixes the non-blocking 0.1.134 hardening issue where a personalized runtime provisioning token remained active after successful local installation and heartbeat.

In 0.1.134 the runtime installed correctly, the heartbeat updated the cloud portal correctly, and the platform became healthy, but the token used by the personalized bundle remained:

    status=active
    used_by_installation_id=NULL
    used_at=NULL

The root cause was that the installer validated local provisioning values but did not call the central runtime register endpoint.

0.1.135 updates local provisioning so that during installation the runtime calls:

    POST /api/v1/customer-runtime/register

using:

    Authorization: Bearer PROVISIONING_TOKEN

This lets the cloud backend execute the existing register_runtime flow and mark the token as used.

## Implemented changes

Patch commit:

    cef65e67 fix(customer-local): register runtime during local provisioning

Version bump commit:

    6489de06 chore(customer-local): bump runtime template to 0.1.135

Modified file:

    deploy/customer-local-template/base/scripts/provision-local.sh

The script now performs the central register call after validating:

    TENANT_CODE
    TENANT_NAME
    CENTRAL_PROVISIONING_URL
    PROVISIONING_TOKEN
    HEARTBEAT_URL
    INSTALLATION_ID

New installer log markers:

    Registering runtime with central GreenBrain
    CENTRAL_RUNTIME_REGISTER_OK
    CENTRAL_RUNTIME_REGISTER_FAILED

Failure behavior:

    exit 41 if HTTP status is not 200
    exit 42 if the response status is not registered

## Backend contract used

The existing cloud backend already supported the required behavior.

Route:

    POST /api/v1/customer-runtime/register

Payload requires:

    tenant_code
    installation_id

The route also accepts optional runtime metadata such as:

    tenant_name
    version
    installed_release_version
    public_backend_url
    connection_mode
    data_mode
    runtime_health
    installation_label

The register flow validates the active provisioning token and then calls:

    mark_runtime_token_used

Expected token result:

    status=used
    used_at populated
    used_by_installation_id=INSTALLATION_ID

## Release artifacts

Release artifacts were built under:

    /opt/greenbrain-platform/releases/customer-local/0.1.135/

Validated files:

    customer-local-0.1.135.tar.gz
    INSTALLA_GREENBRAIN.run
    GreenBrain-Installer.zip
    BUILD-INFO.txt

Build info:

    release_version=0.1.135
    git_commit=6489de06b754c35aa09446f04cf1bd292abf460d

Package validation passed:

    VERSION=0.1.135
    package_version=0.1.135
    wizard_index.html present
    local-sync/password present
    download-bundle endpoint present
    provision-local.sh register markers present
    PREBUILT_NO_BUILD_OK

## GHCR images

0.1.135 did not modify backend or ml-worker source code.

Images were safely retagged from 0.1.134 to 0.1.135 and push/pull validated.

Validated images:

    ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.135
    ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.135

Validated digests:

    backend:   sha256:7f0fca93cbd49310e5c1114a47075a3453a7690f1de96f152ca143cdb2e40d23
    ml-worker: sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680

Image IDs match 0.1.134, as expected.

## Personalized bundle validation

Customer:

    tenant_code=z
    portal_user_email=z@gmail.com

Personalized bundle generated:

    customer-local-0.1.135-z-20260604092858.tar.gz
    GreenBrain-Installer-0.1.135-z-20260604092858.zip

Download validation:

    HTTP=200
    x-greenbrain-bundle-version=0.1.135
    x-greenbrain-bundle-filename=GreenBrain-Installer-0.1.135-z-20260604092858.zip
    x-greenbrain-bundle-sha256=f906a5cfb61ca66f41bb4d6f09a3fcff91f260ba2d0bb54fbca2ecf2b3665614

Bundle inspection:

    VERSION=0.1.135
    package_version=0.1.135
    tenant=z
    token_hint=GO2Cw4
    register patch markers present

Token before install:

    token_hint=GO2Cw4
    status=active
    used_by_installation_id=NULL
    used_at=NULL

Fresh install path:

    /tmp/gb_0135_personalized_install_z_9W2Zuz/package/customer-local-template

Install validation:

    CENTRAL_RUNTIME_REGISTER_OK
    INSTALL_RC=0
    installation_id=15ef3120-26f7-487f-9dda-83f16a4cb272
    backend image=ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.135
    ml-worker image=ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.135
    LOCAL_USER_PROVISION_OK
    local login z@gmail.com / GreenBrain9 HTTP 200
    doctor completed
    EXTENDED_DOCTOR_OK
    RUN_LOCAL_DAILY_ONCE_OK

Token after install:

    token_hint=GO2Cw4
    status=used
    used_by_installation_id=15ef3120-26f7-487f-9dda-83f16a4cb272
    used_at=2026-06-04 09:29:12+00

Cloud portal after heartbeat:

    tenant_code=z
    last_downloaded_release_version=0.1.135
    installed_release_version=0.1.135
    runtime_connection_status=healthy
    latest_installation_id=15ef3120-26f7-487f-9dda-83f16a4cb272
    last_runtime_heartbeat_at=2026-06-04 09:29:31+00

## Final status

0.1.135 is functionally validated.

The runtime provisioning token lifecycle is now correct:

    active -> used

and the token is bound to the actual local installation id.

## Next recommended work

Future hardening can focus on idempotency and update-mode behavior:

    if a runtime is reinstalled with an already-used token and same installation id, allow safe retry
    if a used token is replayed with a different installation id, reject
    document register vs heartbeat lifecycle
    add explicit test coverage for runtime token lifecycle
