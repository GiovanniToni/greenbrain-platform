# GreenBrain Customer Local 0.1.144 — Status and Roadmap

Date: 2026-06-07  
Branch: feat/customer-ops-supabase-foundation  
Release tag target commit: `52e113e4ded6b6f8666c27e2b0b0d8d75910c9e6`

## Summary

Customer-local 0.1.144 finalizes the local technical database credentials UX and the cloud-to-local account bridge.

This release keeps the PostgreSQL local database password separate from the user account password, clarifies this behavior during installation, exposes the local database technical credentials safely from the local account page, and adds a cloud account CTA to open the local account/dashboard on the customer machine.

## Included changes since 0.1.143

Main commits included:

- `13ad3e29` feat(customer-local): expose local database credentials safely
- `bdcd6c03` chore(customer-local): bump runtime template to 0.1.144
- `52e113e4` feat(customer-portal): link cloud account to local account

## Local database credentials behavior

Validated behavior:

1. The local PostgreSQL password remains a technical database password and is different from the user GreenBrain account password.
2. The wizard explains that the local DB password is generated automatically and should be saved safely.
3. The customer does not need to install PostgreSQL manually.
4. PostgreSQL runs inside Docker as part of the GreenBrain local runtime.
5. Local data is stored in the Docker volume used by `greenbrain_local_postgres`.
6. The local account page shows masked technical database metadata.
7. Revealing the local DB password and DATABASE_URL requires confirming the local GreenBrain account password.
8. Wrong password reveal returns HTTP 403.
9. Correct password reveal returns the technical values only from the local runtime.
10. The credentials are not stored or exposed by the cloud account.

## Cloud-to-local account bridge

Validated behavior:

1. The cloud customer account installation tab shows a new card: `Account locale su questo computer`.
2. The card appears between `Runtime locale` and `Bundle & installazione`.
3. It explains that local database credentials are available only from the local runtime on the installed computer.
4. It provides:
   - `Apri account locale` → `http://localhost:8088/account?source=cloud-account`
   - `Apri dashboard locale` → `http://localhost:8088/dashboard?source=cloud-account`

## Release artifacts

Release directory:

`/opt/greenbrain-platform/releases/customer-local/0.1.144/`

Generated artifacts:

- `customer-local-0.1.144.tar.gz`
- `INSTALLA_GREENBRAIN.run`
- `GreenBrain-Installer.zip`
- `BUILD-INFO.txt`
- `package/customer-local-template`
- `universal-installer/*`

`BUILD-INFO.txt`:

- release_version: `0.1.144`
- git_commit: `52e113e4ded6b6f8666c27e2b0b0d8d75910c9e6`

## GHCR images

Validated images:

- `ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.144`
  - digest: `sha256:bec942304ed9ded6a8573ab1e762a61ae8abb665c63d00f2930249c70af26976`
- `ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.144`
  - digest: `sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680`

## Validations

### Static release validation

Passed:

`CUSTOMER_LOCAL_RELEASE_STATIC_VALIDATION_OK version=0.1.144`

Validation confirmed:

- release files exist
- version/package_version are 0.1.144
- `BUILD-INFO.txt` points to final commit `52e113e4ded6b6f8666c27e2b0b0d8d75910c9e6`
- `frontend-dist/index.html` exists
- `frontend-dist/wizard_index.html` exists
- nginx local proxy uses `backend:8000`
- old `host.docker.internal:8008` proxy target absent
- universal installer ZIP structure valid
- embedded ZIP payload version/package_version valid

### Image validation

Passed:

`CUSTOMER_LOCAL_IMAGES_VALIDATION_OK version=0.1.144`

Validation confirmed:

- backend image pulled with expected digest
- ml-worker image pulled with expected digest
- backend runtime/password-sync route markers present
- local password sync DB markers present
- runtime register markers present
- password seed markers present
- ML worker smoke OK

### Fresh install validation

Passed:

`CUSTOMER_LOCAL_FRESH_INSTALL_VALIDATION_OK version=0.1.144 tenant=z`

Validation details:

- personalized portal download OK
- personalized ZIP SHA256: `bfc033417ebb1e7387f94580d4ffce8a4a5d2f29886f6696800e798c58744d0f`
- token hint: `3gFCfI`
- fresh install completed with `INSTALL_RC=0`
- runtime installation id: `8fc5501a-9533-480a-8f33-f0c1eb515e87`
- Docker image tag: `0.1.144`
- backend image: `ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.144`
- ml-worker image: `ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.144`
- backend/frontend healthy
- local login for `z@gmail.com` OK
- local user provisioned with cloud-seeded password
- local password version: `33`
- local password sync status: `synced`
- run-local password sync route returned `no_pending`
- doctor OK
- extended doctor OK
- run-local-daily-once OK
- heartbeat sent healthy to cloud
- cloud heartbeat shows installed/local_agent version 0.1.144

### Extra final feature check

Passed:

- OpenAPI contains `local-db-credentials`
- local login OK
- masked local DB credentials endpoint OK
- reveal with wrong password returns HTTP 403
- reveal with correct password returns DB password and DATABASE_URL, masked in validation output
- served frontend contains:
  - `Account locale su questo computer`
  - `Apri account locale`
  - `Apri dashboard locale`
  - `Credenziali tecniche database locale`
  - `Mostra credenziali tecniche`
  - `Copia DATABASE_URL`

## Remaining untracked files intentionally not included

- `docs/analysis/bundle_plugnplay_plan_20260521.md`
- `docs/analysis/exec_plan_0.1.122.md`
- `docs/analysis/report_0.1.122_20260520.md`
- `releases/customer-local-0.1.122.tar.gz`

## Next recommended phase

- Install/update the real Mac runtime with 0.1.144 and browser-test:
  - cloud account → local account CTA
  - local account DB credentials reveal
  - local dashboard link
- Then proceed with Resend transactional email for automatic self-service password reset delivery.
