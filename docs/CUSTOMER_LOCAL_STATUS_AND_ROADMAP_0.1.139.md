# GreenBrain Customer Local — Status and Roadmap 0.1.139

Date: 2026-06-04
Release version: 0.1.139
Git commit: d6382f54a1e805d44fb945592b7ae9d86ff86d0a
Branch: feat/customer-ops-supabase-foundation

## Release purpose

0.1.139 is a stabilization and release-safety build.

It closes the post-0.1.138 hardening cycle focused on:
- automated regression validation;
- clearer password sync customer-facing UX;
- safer release packaging;
- confirmed GHCR image availability;
- validated fresh personalized install.

No large product feature was added in this release.

## Included changes

### Regression automation

Validated scripts:
- tools/validation/validate_customer_local_release.sh
- tools/validation/validate_customer_local_images.sh
- tools/validation/validate_customer_local_fresh_install.sh

These scripts validate release artifacts, package versions, proxy configuration, run-local markers, GHCR images, fresh install, local login, frontend proxy, backend route, extended doctor, daily once, and heartbeat.

### Password sync UX messages

Customer-facing messages were improved for the local password sync page.

Expected behavior:
- synced: Password locale sincronizzata correttamente.
- no_pending: GreenBrain locale è già allineato. Non ci sono aggiornamenti password da applicare.
- pending_failed / cloud_unreachable: Connessione cloud temporaneamente non disponibile. Riprova tra poco oppure attendi il prossimo controllo automatico.
- other errors: Errore di sincronizzazione.

Technical details remain in the detail payload.

### Safer release packaging

The package excludes non-example env files and local/runtime artifacts.

Explicitly excluded:
- backend-src/.env
- overlay/env/customer-local.env
- overlay/tunnel/cloudflared/cloudflared.env
- venv/
- .venv/
- __pycache__/
- *.pyc
- *.pyo
- *.bak
- *.bak_*
- overlay/logs/
- runtime-reports/
- .pytest_cache/
- .mypy_cache/

Example env files remain present.

## Release artifacts

Release directory:
- releases/customer-local/0.1.139

Build info:
- release_version=0.1.139
- built_at=2026-06-04T14:47:37Z
- git_commit=d6382f54a1e805d44fb945592b7ae9d86ff86d0a

Artifacts:
- BUILD-INFO.txt
- customer-local-0.1.139.tar.gz
- INSTALLA_GREENBRAIN.run
- GreenBrain-Installer.zip
- universal-installer/*

SHA256:
- customer-local-0.1.139.tar.gz: 73c919583d62ec9c20a30630e118946376f54ed42fe1db67e37417c66b2c2930
- GreenBrain-Installer.zip: ad41f8dbbe2e3a2a67e1869f3d4fae010de7ce990f86df0b3066da0cbe422078
- INSTALLA_GREENBRAIN.run: c25e1aa9c6f0399a61c50685b3a726ff8c5fdd40d53337e8a802d754d317102e

## GHCR images

Images were retagged from 0.1.138 to 0.1.139 and pushed.

Backend:
- ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.139
- digest sha256:5393a58cda52e2562340544f15fe64bd04ad9c76b2b0fe6aa6e957d7540a0655

ML worker:
- ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.139
- digest sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680

Image validation:
- CUSTOMER_LOCAL_IMAGES_VALIDATION_OK version=0.1.139

## Static validation

Static validation passed:
- CUSTOMER_LOCAL_RELEASE_STATIC_VALIDATION_OK version=0.1.139
- CUSTOMER_LOCAL_0139_STATIC_VALIDATION_WITH_ENV_EXCLUSION_OK

Validated:
- release directory;
- BUILD-INFO;
- tar payload;
- ZIP payload;
- VERSION/package_version;
- nginx proxy backend:8000;
- old host.docker.internal:8008 proxy target absent;
- run-local backend route markers;
- password sync DB markers;
- frontend markers;
- prebuilt compose without build sections;
- excluded env files absent from tar and ZIP payload.

## Fresh personalized install validation

Fresh install validation passed for tenant z.

Result:
- CUSTOMER_LOCAL_FRESH_INSTALL_VALIDATION_OK version=0.1.139 tenant=z

Personalized bundle:
- GreenBrain-Installer-0.1.139-z-20260604145920.zip
- SHA256 57552ec18c02837b51363908976a0d35205762cf7f4560225937668ad0eaa6b6

Runtime validation:
- installation_id: ae148ae1-d380-42ba-bc1c-a5d7dbd8bced
- token hint: FVMEsI
- backend image: ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.139
- ml-worker image: ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.139
- frontend proxy run-local: HTTP 200 no_pending
- direct backend run-local: HTTP 200 no_pending
- local login z@gmail.com: HTTP 200
- EXTENDED_DOCTOR_OK
- RUN_LOCAL_DAILY_ONCE_OK
- heartbeat sent successfully
- installed_release_version: 0.1.139
- local_agent_version: 0.1.139
- runtime_health: healthy

## Known notes

Intentional untracked files remain outside release:
- docs/analysis/bundle_plugnplay_plan_20260521.md
- docs/analysis/exec_plan_0.1.122.md
- docs/analysis/report_0.1.122_20260520.md
- releases/customer-local-0.1.122.tar.gz

Do not include them unless explicitly intended.

## Recommended next priorities

### 0.1.140 — Wizard update/reinstall clarity

Improve installer wizard language and flow around:
- new installation;
- version update;
- clean reinstall;
- keep local data;
- full reset;
- existing GreenBrain stack detected;
- ports occupied by GreenBrain stack;
- ports occupied by external process.

### 0.1.141 — Token and installation cleanup tooling

Add admin/ops utility to:
- list active/used/revoked tokens;
- revoke old tokens;
- archive old test installations;
- keep only latest healthy installation per tenant when requested.

### Later — Mature account runtime controls

Continue improving /account with:
- installation state;
- cloud/local password status;
- last heartbeat;
- installed/downloaded/available version;
- download update button;
- local password sync button;
- open runtime button;
- clear pending-action messages.
