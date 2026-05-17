# GreenBrain Customer Local — Status and Roadmap 0.1.109

## Release

- Version: 0.1.109
- Tag: customer-local-0.1.109
- Bundle: /opt/greenbrain-platform/releases/customer-local/0.1.109/customer-local-0.1.109.tar.gz
- One-click installer: /opt/greenbrain-platform/releases/customer-local/0.1.109/INSTALLA_GREENBRAIN.run
- Universal installer: /opt/greenbrain-platform/releases/customer-local/0.1.109/GreenBrain-Installer.zip

## Milestone

0.1.109 validates the correct GHCR prebuilt install path with automatic image tag selection from the package VERSION.

The installer now sets:

GREENBRAIN_IMAGE_TAG="$(cat VERSION)"

when GREENBRAIN_IMAGE_TAG is not already provided.

This prevents macOS/Windows/customer installs from falling back to the `latest` image tag unintentionally.

## GHCR images

Validated anonymous pulls:

- ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.109
- ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.109

Published digests:

- backend: sha256:50a9d94ff9b80ec48f95a5df3e7bf1fc9741ffae0c2e7546156243472723b915
- ml-worker: sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680

## Package validation

Validated:

- docker-compose.prebuilt.yml is included in the bundle
- docker-compose.prebuilt.yml has no build sections
- install.sh prints Docker image tag
- install.sh defaults GREENBRAIN_IMAGE_TAG from package VERSION
- install.sh defaults to prebuilt images
- install.sh still has fallback to local Docker build if prebuilt startup fails
- VERSION and package_version are 0.1.109

## Fresh server validation

Fresh test path:

/tmp/gb_fresh_0109_prebuilt_auto_tag_20260517_223927/package/customer-local-template

Environment:

- GREENBRAIN_IMAGE_TAG unset
- GREENBRAIN_USE_PREBUILT_IMAGES unset
- GREENBRAIN_PROVISIONING_TOKEN=dev_test_token
- GREENBRAIN_CONFIGURE_SOURCE_DB=no

Validated output:

- Docker image tag: 0.1.109
- Using prebuilt Docker images
- No local build
- No fallback
- Backend image: ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.109
- VERSION/package_version: 0.1.109
- backend healthy
- frontend healthy
- doctor-local-extended.sh OK
- Source DB not configured as expected
- train_missing rc=0
- predict_all rc=0
- heartbeat central healthy
- RUN_LOCAL_DAILY_ONCE_OK

Heartbeat installation id:

b114252c-beb8-46c6-9e02-62f182734cf5

## Known open items

### macOS localhost issue

On macOS, Windsurf can bind/intercept 127.0.0.1 on ports 8008/8088, while localhost resolves through IPv6 and works correctly.

Next fix should prefer localhost in customer-facing URLs and launcher open-browser behavior on macOS.

### Portal personalization

The current generic installer does not yet provision the local greenbrain_users row from the authenticated portal user.

Observed local table:

greenbrain_users exists but has zero rows after generic install.

Next phase should connect portal download/personalized bundle to local user provisioning fields:

- LOCAL_CUSTOMER_EMAIL
- LOCAL_CUSTOMER_FULL_NAME
- LOCAL_CUSTOMER_TENANT_CODE
- LOCAL_CUSTOMER_HOME_HOST
- LOCAL_CUSTOMER_HOME_PATH
- user_role
- can_access_app

### Wizard UX

The wizard now completes correctly, but the install view should be improved:

- show a progress/loading state first
- hide raw logs by default
- provide a button to expand technical logs
- after completion, open local GreenBrain using localhost, not 127.0.0.1 on macOS

## Next recommended release

0.1.110 should focus on installer UX and localhost behavior:

1. Replace 127.0.0.1 customer-facing links with localhost where appropriate.
2. Improve wizard progress display.
3. Keep logs expandable but hidden by default.
4. Retest universal installer on macOS.
5. Then proceed to portal-personalized installer/user provisioning.
