# GreenBrain Customer Local — Status and Roadmap 0.1.132

## Release

Release version: 0.1.132

Main goal: complete automatic password synchronization using heartbeat actions, without adding a dedicated password-sync cron.

## Summary

Release 0.1.132 introduces a robust cloud-first password synchronization flow:

1. Password changes remain cloud-only.
2. Cloud stores the updated password hash and increments password_version.
3. Cloud marks the password sync state as pending.
4. Customer local runtime sends its existing heartbeat.
5. Cloud heartbeat response includes an action when needed:
   - type: password_sync_required
   - password_version: target password version
   - email: customer email
   - required_at: cloud timestamp
6. Local heartbeat script consumes the action and runs password sync.
7. Local runtime updates greenbrain_users.hashed_password and password metadata.
8. Local runtime sends ACK to cloud.
9. Cloud marks the password sync state as synced.

No dedicated password-sync cron is enabled. The existing heartbeat channel is used as the runtime control plane.

## Key changes

### Cloud heartbeat actions

Cloud heartbeat response now includes an actions field.

When a tenant has a pending password sync, the cloud returns a password_sync_required action.

### Local runtime heartbeat action consumer

runtime-heartbeat.sh now:

- stores the heartbeat response;
- parses actions;
- detects password_sync_required;
- triggers sync_password_from_cloud.sh.

The script supports two execution modes:

- HEARTBEAT_ACTION_PASSWORD_SYNC_MODE=direct
- HEARTBEAT_ACTION_PASSWORD_SYNC_MODE=scheduler

This makes it robust when launched inside the runtime container or from the host where Docker is available.

### Password seed from bundle

The personalized bundle keeps the password metadata introduced in 0.1.131:

- LOCAL_CUSTOMER_PASSWORD_VERSION
- LOCAL_CUSTOMER_PASSWORD_CHANGED_AT
- LOCAL_CUSTOMER_PASSWORD_SYNC_STATUS
- LOCAL_CUSTOMER_PASSWORD_SEED_SOURCE

The local DB is initialized with cloud password metadata when the customer-local bundle is personalized.

## Validation

### Package validation

Validated package:

- VERSION=0.1.132
- package_version=0.1.132
- no unexpected secret files
- no password-sync cron
- prebuilt compose has no build sections
- heartbeat action markers present
- password seed markers present

### GHCR images

Validated GHCR images:

- ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.132
- ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.132

Backend digest:

ghcr.io/giovannitoni/greenbrain-customer-backend@sha256:8f5214488b4815d4e58619dd57fe4e922f95fbccf11bc1f195b50e0322196855

ML worker digest:

ghcr.io/giovannitoni/greenbrain-customer-ml-worker@sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680

### Personalized bundle validation

Generated personalized bundle for tenant z:

- GreenBrain-Installer-0.1.132-z-20260603151118.zip
- customer-local-0.1.132-z-20260603151115.tar.gz

Download endpoint:

GET /api/v1/customer-portal/download-bundle

Validated headers:

- X-GreenBrain-Bundle-Version: 0.1.132
- X-GreenBrain-Bundle-Filename: GreenBrain-Installer-0.1.132-z-20260603151118.zip
- anti-cache headers enabled
- SHA256 present and verified

Bundle metadata:

- LOCAL_CUSTOMER_PASSWORD_VERSION=6
- LOCAL_CUSTOMER_PASSWORD_SYNC_STATUS=synced
- LOCAL_CUSTOMER_PASSWORD_SEED_SOURCE=cloud_seed

### Fresh install validation

Fresh install from personalized 0.1.132 tar succeeded:

- INSTALL_RC=0
- backend image: ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.132
- backend healthy
- frontend healthy
- LOCAL_USER_PROVISION_OK
- local DB initialized with password_version=6
- password_change_source=cloud_seed
- password_last_sync_status=synced

Login validation after fresh install:

- GreenBrain4 returned HTTP 200
- GreenBrain3 returned HTTP 401

### Heartbeat action password sync validation

Cloud password change test:

- changed password from GreenBrain4 to GreenBrain5
- cloud moved to password_version=7
- cloud status became pending
- heartbeat precheck returned password_sync_required version=7

Before sync, local runtime remained on:

- password_version=6
- GreenBrain4 HTTP 200
- GreenBrain5 HTTP 401

Then only runtime-heartbeat.sh was executed. No manual password sync command was run.

Heartbeat consumed the action:

- HEARTBEAT_ACTION_PASSWORD_SYNC_REQUIRED version=7
- HEARTBEAT_ACTION_PASSWORD_SYNC_MODE=scheduler
- PASSWORD_SYNC_PENDING_FOUND email=z@gmail.com version=7
- PASSWORD_SYNC_LOCAL_UPDATED email=z@gmail.com version=7
- PASSWORD_SYNC_ACK_HTTP=200 status=synced response_status=password_sync_synced version=7
- PASSWORD_SYNC_DONE

After sync:

- local DB password_version=7
- password_change_source=cloud_sync
- password_last_sync_status=synced
- GreenBrain4 HTTP 401
- GreenBrain5 HTTP 200
- second heartbeat returned actions=[]

Cloud final validation:

- password_version=7
- password_last_sync_status=synced
- failed_ack_version_7=0
- synced_ack_version_7=1
- heartbeat after sync returned actions=[]

## Architectural decision

Do not add a dedicated password-sync cron.

The selected design is:

cloud change-password
-> cloud pending state
-> heartbeat action
-> local sync
-> cloud ACK synced

This avoids duplicate polling and uses the heartbeat as the runtime control plane.

## Remaining work

Recommended next steps for 0.1.133:

1. Add optional immediate browser-triggered local sync after cloud password change when the user is on the same PC as the local runtime.
2. Add UI status in /account -> Sicurezza:
   - cloud password version
   - local sync status
   - last synced at
   - pending/failed indication
3. Improve password sync script verbosity by suppressing harmless repeated schema NOTICE lines or moving local schema ensure to install/migration phase only.
4. Continue testing on real Mac update path from 0.1.131 to 0.1.132.
