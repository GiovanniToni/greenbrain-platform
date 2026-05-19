# GreenBrain Customer Local — Status and Roadmap 0.1.111

## Release

- Version: 0.1.111
- Tag: customer-local-0.1.111
- Bundle: /opt/greenbrain-platform/releases/customer-local/0.1.111/customer-local-0.1.111.tar.gz
- One-click installer: /opt/greenbrain-platform/releases/customer-local/0.1.111/INSTALLA_GREENBRAIN.run
- Universal installer: /opt/greenbrain-platform/releases/customer-local/0.1.111/GreenBrain-Installer.zip

## Milestone

0.1.111 fixes a macOS installer race condition where the runtime was healthy, but the wizard could mark installation as failed because `doctor-local.sh` performed a single immediate curl check and sometimes received a transient connection reset.

## Key fix

`doctor-local.sh` now:

- retries backend health on `http://localhost:8008/health`
- retries frontend health on `http://localhost:8088`
- waits up to 30 attempts with 2 seconds between attempts
- prints clear waiting/failed diagnostics
- uses `docker-compose.prebuilt.yml` for `ps` when available

## GHCR images

Validated anonymous pulls:

- ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.111
- ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.111

Published digests:

- backend: sha256:50a9d94ff9b80ec48f95a5df3e7bf1fc9741ffae0c2e7546156243472723b915
- ml-worker: sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680

## Fresh validation

Fresh test path:

/tmp/gb_fresh_0111_doctor_retry_20260519_093553/package/customer-local-template

Validated:

- VERSION/package_version 0.1.111
- Package includes docker-compose.prebuilt.yml
- Package includes doctor-local.sh retry logic
- Installer auto-derived Docker image tag 0.1.111
- Installer used GHCR prebuilt images by default
- No local build fallback occurred
- Backend image: ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.111
- ML worker image: ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.111
- Backend health OK via localhost
- Frontend HTTP 200 via localhost
- doctor-local completed
- INSTALL COMPLETED
- doctor-local-extended OK
- DB checks OK
- ML imports OK
- JWT SSO consistency OK
- Source DB not configured, skipped cleanly
- run-local-daily-once OK
- pipeline raw->fact->dense->features OK
- train_missing OK rc=0
- predict_all OK rc=0
- central heartbeat healthy with installed_release_version/local_agent_version 0.1.111

## Remaining required validation

- real macOS retest with GreenBrain-Installer.zip 0.1.111
- Windows retest with GreenBrain-Installer.zip 0.1.111

## Next roadmap

### 0.1.112 — personalized customer download

- Patch customer delivery download to prefer customer-specific bundle when available.
- Avoid bypassing `bundle_local_path` with generic latest `GreenBrain-Installer.zip`.
- Decide whether personalized delivery should generate a universal `GreenBrain-Installer.zip` or a tar.gz only.

### 0.1.113 — local user provisioning

- Use `LOCAL_CUSTOMER_EMAIL`, `LOCAL_CUSTOMER_FULL_NAME`, `LOCAL_CUSTOMER_HOME_PATH`, `LOCAL_CUSTOMER_TENANT_CODE`.
- Insert/update `public.greenbrain_users`.
- Ensure `can_access_app=true`, `user_role=customer_admin`.
- Validate Dashboard/Riordino visibility after login.
