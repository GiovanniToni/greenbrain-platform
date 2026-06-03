# GreenBrain Customer Local — Status and Roadmap 0.1.133

## Release

Release version: `0.1.133`

Main goal: add a local password sync trigger endpoint and frontend best-effort trigger after cloud password change, while keeping heartbeat-based password sync as the guaranteed automatic fallback.

## Summary

Release `0.1.133` extends the password synchronization architecture introduced in `0.1.132`.

The stable guaranteed path remains:

1. User changes password on the cloud account.
2. Cloud stores the new hash and increments `password_version`.
3. Cloud marks the local password sync status as `pending`.
4. Customer-local runtime sends the existing heartbeat.
5. Cloud heartbeat response includes a `password_sync_required` action when needed.
6. Runtime applies the cloud hash locally.
7. Runtime sends ACK back to the cloud.
8. Cloud marks the password sync as `synced`.

Release `0.1.133` adds an additional local runtime API endpoint:

`POST /api/v1/customer-runtime/password-sync/run-local`

This endpoint allows the local runtime to check for a pending cloud password update and apply it immediately when called.

## Important browser finding

A direct browser call from `https://www.greenbrain.it` to `http://localhost:8008` is blocked by Safari/browser mixed-content policy, even when CORS and Private Network Access headers are present.

Therefore, immediate browser-triggered sync is best-effort only in this release.

The guaranteed automatic mechanism remains the heartbeat action flow.

## Validated commits

Main feature commit:

`05f497fb feat(customer-local): add local password sync trigger endpoint`

Runtime version bump:

`0217e471 chore(customer-local): bump runtime template to 0.1.133`

## Files changed in feature commit

- `apps/frontend/src/pages/CustomerPortalDashboard.tsx`
- `deploy/customer-local-template/base/backend-src/app/api/v1/customer_runtime.py`
- `deploy/customer-local-template/base/backend-src/app/db/users.py`
- `deploy/customer-local-template/base/backend-src/app/main.py`
- `deploy/customer-local-template/docker-compose.local.yml`
- `deploy/customer-local-template/docker-compose.prebuilt.yml`

Note: `customer_runtime.py` had to be force-added because `.gitignore` includes `**/v**/`.

## Backend/runtime changes

The local runtime now includes:

`POST /api/v1/customer-runtime/password-sync/run-local`

The endpoint:

- uses tenant and installation identity from the local runtime environment;
- calls the central pending-password-sync API;
- applies the cloud password hash locally when pending;
- records local password sync event metadata;
- sends ACK to cloud;
- returns `synced` or `no_pending`.

Validated markers:

- `password-sync/run-local`
- `GreenBrainCustomerLocal/0.1.133 runtime-password-sync`
- `apply_cloud_password_sync`

## CORS and Private Network Access

The local backend adds:

`Access-Control-Allow-Private-Network: true`

for GreenBrain origins when running in `client-local` mode.

Validated with:

- `Origin: https://www.greenbrain.it`
- `Access-Control-Request-Private-Network: true`

Response includes:

- `access-control-allow-origin: https://www.greenbrain.it`
- `access-control-allow-private-network: true`

## Frontend behavior

The cloud account security tab now tries a best-effort local sync after successful cloud password change.

If local sync succeeds, the UI shows:

`Password aggiornata correttamente. GreenBrain locale è stato sincronizzato subito.`

If browser policy blocks the local call, the UI falls back to:

`Password aggiornata correttamente. La password è aggiornata sul cloud; GreenBrain locale si allineerà automaticamente al prossimo controllo.`

This fallback is expected and valid because heartbeat sync is the guaranteed mechanism.

## Nginx/public route fix

During validation, public route `/api/v1/auth/change-password` was found to route incorrectly to the old auth backend.

Nginx was patched so the exact route goes to:

`http://127.0.0.1:8002`

Validation:

`POST https://www.greenbrain.it/api/v1/auth/change-password` without token returns:

`HTTP 403 {"detail":"Not authenticated"}`

This confirms the route now reaches `dev_backend`.

## GHCR images

Backend image was rebuilt from the `0.1.133` release package because backend code changed.

Validated backend image:

`ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.133`

Digest:

`sha256:7f0fca93cbd49310e5c1114a47075a3453a7690f1de96f152ca143cdb2e40d23`

ML worker was retagged from `0.1.132` because it did not change.

Validated ML worker image:

`ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.133`

Digest:

`sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680`

Pull validation confirmed the backend image contains:

- `PULLED_HAS_RUN_LOCAL=True`
- `PULLED_HAS_USER_AGENT=True`
- `PULLED_HAS_PNA=True`
- `PULLED_HAS_APPLY_SYNC=True`

## Release artifacts

Release directory:

`/opt/greenbrain-platform/releases/customer-local/0.1.133/`

Artifacts:

- `customer-local-0.1.133.tar.gz`
- `INSTALLA_GREENBRAIN.run`
- `GreenBrain-Installer.zip`
- `BUILD-INFO.txt`
- `package/`
- `universal-installer/`

BUILD-INFO:

- `release_version=0.1.133`
- `built_at=2026-06-03T22:52:40Z`
- `git_commit=0217e471adabd7c246381b0e358f87d73433465c`

## Universal installer validation

The universal installer ZIP is valid.

The ZIP contains:

- `INSTALLA_GREENBRAIN_LINUX.run`
- `INSTALLA_GREENBRAIN_MAC.command`
- `INSTALLA_GREENBRAIN_WINDOWS.bat`
- `INSTALLA_GREENBRAIN_WINDOWS.ps1`
- `LEGGIMI_INSTALLAZIONE.txt`
- `GreenBrain-Install.desktop`

The Linux/Mac run file is self-extracting and contains marker:

`__GREENBRAIN_ARCHIVE_BELOW__`

Embedded payload contains:

- `VERSION=0.1.133`
- `package_version=0.1.133`
- `password-sync/run-local`
- `Access-Control-Allow-Private-Network`
- `apply_cloud_password_sync`

## Fresh prebuilt install validation

Fresh install with personalized `z` environment succeeded.

Validation result:

- `INSTALL_RC=0`
- `BACKEND_IMAGE=ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.133`
- `ML_IMAGE=ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.133`
- `HAS_RUN_LOCAL=True`
- `HAS_USER_AGENT=True`
- `HAS_PNA=True`
- `HAS_APPLY_SYNC=True`
- `EXTENDED_DOCTOR_OK`
- `RUN_LOCAL_DAILY_ONCE_OK`

Heartbeat was received by central cloud with:

- `installed_release_version=0.1.133`
- `local_agent_version=0.1.133`
- `runtime_health=healthy`
- `actions=[]`

Fresh test installation id:

`27f9be72-eea5-4ac0-b47a-fb5b582844d6`

## Personalized portal download validation

Public customer portal download was validated using the correct endpoint:

`/api/v1/customer-portal/download-bundle`

Incorrect endpoint discovered and not used:

`/api/v1/customer-portal/download-local-bundle`

Validated public download result:

- `HTTP 200`
- `GreenBrain-Installer-0.1.133-z-20260603231358.zip`
- `X-GreenBrain-Bundle-Version: 0.1.133`
- `X-GreenBrain-Bundle-SHA256: 7c3c2c78819de592aa554a3e3860743dc9ea1bca4765f7e80f904e1d68a117b1`

Generated artifacts:

- `runtime-reports/customer-bundles/GreenBrain-Installer-0.1.133-z-20260603231358.zip`
- `runtime-reports/customer-bundles/customer-local-0.1.133-z-20260603231358.tar.gz`

SHA256:

- `GreenBrain-Installer-0.1.133-z-20260603231358.zip`
  `7c3c2c78819de592aa554a3e3860743dc9ea1bca4765f7e80f904e1d68a117b1`

- `customer-local-0.1.133-z-20260603231358.tar.gz`
  `79961b5b713d617d4650ad207b6d26697bf1757ef96a6b471040ac173376d90d`

The downloaded ZIP matched the server ZIP.

Personalized TAR and ZIP self-extract payload contain:

- `VERSION=0.1.133`
- `package_version=0.1.133`
- `TENANT_CODE=z`
- `LOCAL_CUSTOMER_EMAIL=z@gmail.com`
- `LOCAL_CUSTOMER_PASSWORD_VERSION=10`
- `LOCAL_CUSTOMER_PASSWORD_SYNC_STATUS=synced`
- `password-sync/run-local`
- `Access-Control-Allow-Private-Network`
- `apply_cloud_password_sync`

After download, customer portal state:

- `installed_release_version=0.1.133`
- `latest_available_release_version=0.1.133`
- `last_downloaded_release_version=0.1.133`
- `runtime_connection_status=healthy`
- `runtime_local_agent_version=0.1.133`
- `platform_ready=True`

## Known limitation

Immediate browser-to-local sync from `https://www.greenbrain.it` to `http://localhost:8008` is blocked by Safari/browser mixed-content policy.

This is not a backend failure.

The correct next improvement is to implement a browser-safe immediate local sync mechanism.

## Recommended 0.1.134 roadmap

Preferred candidates:

1. Local top-level sync page:
   - cloud password change opens or navigates to `http://localhost:8088/local-sync/password`;
   - the local page calls local backend same-origin;
   - avoids HTTPS-to-HTTP mixed content fetch.

2. Local HTTPS helper:
   - expose local runtime on HTTPS with a trusted/local certificate strategy.

3. Custom protocol:
   - `greenbrain://sync-password`.

The recommended first path is the local top-level sync page because it is simpler and avoids browser mixed-content restrictions.
