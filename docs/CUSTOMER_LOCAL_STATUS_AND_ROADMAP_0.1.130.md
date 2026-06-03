# GreenBrain Customer Local — Status and Roadmap 0.1.130

## Release summary

Release `0.1.130` completes the first validated customer-local password synchronization milestone.

This release keeps password changes cloud-only, adds a manual local password synchronization job, validates the runtime package with GHCR prebuilt images, and intentionally leaves automatic password-sync cron disabled until further controlled testing.

## Git and release state

- Branch: `feat/customer-ops-supabase-foundation`
- Release commit: `d3c2f29a chore(customer-local): bump runtime template to 0.1.130`
- Tag: `customer-local-0.1.130`
- Tag target: `d3c2f29a`
- Release path: `/opt/greenbrain-platform/releases/customer-local/0.1.130/`

Release artifacts:

- `customer-local-0.1.130.tar.gz`
- `GreenBrain-Installer.zip`
- `BUILD-INFO.txt`
- `package/customer-local-template/`
- `universal-installer/`

BUILD-INFO:

- `release_version=0.1.130`
- `built_at=2026-06-03T08:26:49Z`
- `git_commit=d3c2f29a0b176d5a10ac8ce0bf7ed2dcbad53c45`

## GHCR images

Backend image:

- `ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.130`
- digest: `sha256:52ed69e276d482745d8bbbb04406d8cbd1fccee0a27a4a20c01ff3b6e48f230b`

ML worker image:

- `ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.130`
- digest: `sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680`

Both images were pushed and pull-validated.

## Package validation

Validated package properties:

- `VERSION = 0.1.130`
- `release-manifest.yml` contains `package_version: 0.1.130`
- `docker-compose.prebuilt.yml` contains no `build:` sections
- no real secret env files are included
- no unwanted `.bak`, `.bak_*`, `__pycache__`, `.pyc`, or runtime log files are included
- universal installer ZIP contains Linux, macOS, Windows launchers and README
- installer derives `GREENBRAIN_IMAGE_TAG` from package `VERSION`
- prebuilt image path is default

## Password-change architecture

Password changes must happen only in the cloud customer account area.

Intended user-facing path:

- `www.greenbrain.it`
- `Il mio account`
- `Sicurezza`
- `Cambia password`

The customer-local runtime must not be the place where the user changes password.

When the customer changes password in the cloud:

1. the current password is verified;
2. the new password is validated;
3. only the hash is stored;
4. `password_version` is incremented;
5. `password_changed_at` is updated;
6. `password_change_source` is set to `cloud_api`;
7. customer-local users are marked with `password_last_sync_status = pending`;
8. `password_sync_required_at` is updated.

Passwords are never stored or transported in clear text.

## Cloud runtime sync endpoints

Cloud runtime endpoints added for customer-local password synchronization:

- `POST /api/v1/customer-runtime/password-sync/pending`
- `POST /api/v1/customer-runtime/password-sync/ack`

The pending endpoint returns a pending password sync only when the runtime token is valid for the tenant and installation.

The ACK endpoint records local sync result:

- `synced`
- `failed`

Cloud tracks:

- `password_last_synced_at`
- `password_last_sync_status`
- `password_last_sync_error`
- `password_last_sync_attempt_at`

## Local password sync job

0.1.130 includes a manual local job:

`base/orchestration/jobs/runtime/sync_password_from_cloud.sh`

The script:

1. loads `overlay/env/customer-local.env`;
2. loads `overlay/provisioning/local-runtime.env`;
3. calls the cloud pending endpoint using `PROVISIONING_TOKEN`;
4. receives only `hashed_password`, never clear text;
5. updates local `public.greenbrain_users`;
6. writes local password event metadata;
7. ACKs the cloud as `synced` or `failed`;
8. masks password hashes in logs.

Manual execution example:

`docker compose -f docker-compose.prebuilt.yml --env-file overlay/env/customer-local.env exec -T scheduler sh -lc 'cd /workspace && bash base/orchestration/jobs/runtime/sync_password_from_cloud.sh'`

## Cron policy in 0.1.130

Password sync is intentionally not enabled in cron.

Current scheduler cron remains:

- every 5 minutes: `base/scripts/runtime-heartbeat.sh`
- every day at 21:05: `base/scripts/run-local-daily-once.sh`

There is no automatic `sync_password_from_cloud.sh` cron entry in 0.1.130.

Automatic sync is deferred to a later release after more testing.

## Wizard and installer behavior

The wizard generates:

- `overlay/env/customer-local.env`
- `overlay/provisioning/local-runtime.env`

The runtime env includes:

- `TENANT_CODE`
- `CENTRAL_AUTH_URL`
- `PROVISIONING_TOKEN`
- `INSTALLATION_ID`
- `HEARTBEAT_URL`

The installer:

1. runs preflight checks;
2. runs provisioning;
3. derives Docker image tag from package `VERSION`;
4. uses GHCR prebuilt images by default;
5. starts local Postgres, backend, frontend, scheduler, and ML worker;
6. verifies backend health;
7. verifies local DB credentials;
8. provisions the local customer user when credentials or hash are present;
9. runs doctor;
10. optionally skips Source DB configuration when configured to do so.

## Fresh install validation

Fresh install test path:

`/tmp/gb_fresh_0130_manual_pw_sync_20260603_103401/package/customer-local-template`

Fresh install result:

- `INSTALL_RC=0`
- backend healthy
- frontend HTTP 200
- backend image: `ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.130`
- manual password sync script present and executable
- password sync cron not enabled
- manual password sync with `dev_test_token` failed non-blocking with expected `runtime_token_invalid`
- `EXTENDED_DOCTOR_OK`
- `DOCTOR_RC=0`
- `RUN_LOCAL_DAILY_ONCE_OK`
- `DAILY_RC=0`
- central heartbeat received as healthy with local agent version `0.1.130`

## Known non-blocking observations

Manual password sync in the fresh install validation returned:

- `PASSWORD_SYNC_PENDING_HTTP=400`
- `runtime_token_invalid`

This is expected because the fresh test used `dev_test_token`, not a valid customer runtime token.

The script handled this as non-blocking.

## Security notes

- Passwords are never stored in clear text.
- Cloud-to-local sync transports only password hashes.
- Runtime token validation is required before returning pending password sync data.
- Local password sync logs mask `hashed_password`.
- Local password sync is not automatic in 0.1.130.
- Local password change is disabled for client-local environments and should be managed through the cloud customer account.

## Remaining intentionally untracked files

These files remain intentionally untracked and are not part of 0.1.130:

- `docs/analysis/bundle_plugnplay_plan_20260521.md`
- `docs/analysis/exec_plan_0.1.122.md`
- `docs/analysis/report_0.1.122_20260520.md`
- `releases/customer-local-0.1.122.tar.gz`

## Roadmap after 0.1.130

### 0.1.131 candidate

Primary target:

- controlled automatic password sync cron after additional validation.

Before enabling cron:

1. test manual sync on a real customer-local runtime after another cloud password change;
2. verify cloud pending and ACK state after multiple runs;
3. verify idempotency when no pending sync exists;
4. verify failure recovery from `failed` back to `pending`;
5. verify no sensitive payload appears in logs;
6. decide frequency, likely every 5 or 10 minutes;
7. add operator-visible status in account/security UI if needed.

## Final status

0.1.130 is closed, validated, tagged, and pushed.

Next recommended action:

1. commit this status document;
2. push branch;
3. plan 0.1.131 with analysis-first approach.
