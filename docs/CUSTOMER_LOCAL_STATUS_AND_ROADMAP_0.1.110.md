# GreenBrain Customer Local — Status and Roadmap 0.1.110

## Release

- Version: 0.1.110
- Tag: customer-local-0.1.110
- Bundle: /opt/greenbrain-platform/releases/customer-local/0.1.110/customer-local-0.1.110.tar.gz
- One-click installer: /opt/greenbrain-platform/releases/customer-local/0.1.110/INSTALLA_GREENBRAIN.run
- Universal installer: /opt/greenbrain-platform/releases/customer-local/0.1.110/GreenBrain-Installer.zip

## Milestone

0.1.110 validates customer-local install with GHCR prebuilt images, automatic image tag from package VERSION, and improved macOS localhost/wizard UX hardening.

## Key fixes

- Host-facing install links now use `localhost` instead of `127.0.0.1`.
- `doctor-local.sh` now checks:
  - `http://localhost:8008/health`
  - `http://localhost:8088`
- Installer summary prints localhost URLs.
- Mac launcher/wizard user-facing URL uses `localhost`.
- Wizard UX now hides technical logs behind `Mostra dettagli tecnici`.
- Wizard shows a visible status box/spinner and clear completed/failed messages.
- Preflight external-port error now prints the owning process via `lsof`.
- macOS preflight gives explicit guidance to close apps such as Windsurf when they occupy GreenBrain ports.

## GHCR images

Validated anonymous pulls:

- ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.110
- ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.110

Published digests:

- backend: sha256:50a9d94ff9b80ec48f95a5df3e7bf1fc9741ffae0c2e7546156243472723b915
- ml-worker: sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680

## Package validation

Validated package includes:

- docker-compose.local.yml
- docker-compose.prebuilt.yml
- install.sh
- INSTALL_GREENBRAIN.sh
- VERSION
- release-manifest.yml
- base/apps/local-installer-wizard/wizard.py
- base/scripts/doctor-local.sh
- base/scripts/preflight-local-install.sh

Packaged version checks:

- VERSION = 0.1.110
- package_version = 0.1.110

Packaged install behavior:

- `Docker image tag: 0.1.110`
- `Using prebuilt Docker images`
- Backend URL uses `http://localhost:8008/health`
- Frontend URL uses `http://localhost:8088`

## Fresh validation

Fresh test path:

/tmp/gb_fresh_0110_prebuilt_localhost_20260517_235717/package/customer-local-template

Environment:

- GREENBRAIN_IMAGE_TAG unset
- GREENBRAIN_USE_PREBUILT_IMAGES unset
- GREENBRAIN_PROVISIONING_TOKEN=dev_test_token
- GREENBRAIN_CONFIGURE_SOURCE_DB=no

Validated:

- Installer auto-derived `GREENBRAIN_IMAGE_TAG=0.1.110`
- Installer used GHCR prebuilt images by default
- No local Docker build fallback occurred
- Backend container image: ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.110
- ML worker image: ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.110
- Backend health OK via localhost
- Frontend HTTP 200 via localhost
- doctor-local-extended OK
- DB checks OK
- ML imports OK
- JWT SSO consistency OK
- Source DB not configured, skipped cleanly
- run-local-daily-once OK
- pipeline raw->fact->dense->features OK
- train_missing OK rc=0
- predict_all OK rc=0
- central heartbeat healthy with installed_release_version/local_agent_version 0.1.110

## Remaining known issues

1. Universal installer should be retested on real macOS and Windows with 0.1.110.
2. Mac caveat: tools such as Windsurf may bind `127.0.0.1:8008/8088`; 0.1.110 improves user-facing links to localhost and preflight diagnostics, but real Mac retest is still required.
3. Customer download currently prefers the generic latest `GreenBrain-Installer.zip`; personalized bundle/download behavior still needs correction.
4. Local `greenbrain_users` provisioning is not yet automatic, so customer user/email/role/home_path are not guaranteed to appear in the local DB after a generic install.
5. Post-install login/routing must be fixed so customer users land in the local app with Dashboard/Riordino sections.

## Next roadmap

### 0.1.111 — personalized download correctness

- Analyze and patch `customer_delivery_service.resolve_bundle_download`.
- Prefer customer-specific `bundle_local_path` when available.
- Keep safe fallback to latest generic universal installer.
- Verify whether delivery bundle should be `.tar.gz` or personalized `GreenBrain-Installer.zip`.

### 0.1.112 — local user provisioning

- Use personalized env fields:
  - LOCAL_CUSTOMER_EMAIL
  - LOCAL_CUSTOMER_FULL_NAME
  - LOCAL_CUSTOMER_TEMP_PASSWORD
  - LOCAL_CUSTOMER_TENANT_CODE
  - LOCAL_CUSTOMER_HOME_HOST
  - LOCAL_CUSTOMER_HOME_PATH
- Insert/update `public.greenbrain_users` during provisioning/install.
- Ensure `can_access_app=true`, `user_role=customer_admin`, and correct `home_path`.
- Validate local login exposes Dashboard/Riordino sections.

### 0.1.113 — real OS installer validation

- Retest 0.1.110+ universal installer on macOS.
- Retest 0.1.110+ universal installer on Windows.
- Confirm GHCR prebuilt path without fallback on both systems.
