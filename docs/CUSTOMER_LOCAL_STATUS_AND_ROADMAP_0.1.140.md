# GreenBrain Customer Local — Status and Roadmap 0.1.140

Date: 2026-06-04
Release version: 0.1.140
Git commit: e5b1097193d9c1a991d8c040e2d85ec0b87e3931
Branch: feat/customer-ops-supabase-foundation

## Release purpose

0.1.140 is a small UX and installer-clarity release.

It focuses on:

- clearer wizard wording for install/update versus reset;
- clearer preflight port messages;
- preserving the existing install/update logic;
- validating package, GHCR images, and fresh personalized install.

No runtime behavior, Docker logic, database logic, password sync logic, port mapping, or install mode logic was intentionally changed.

## Included changes

### Wizard install/reset wording

Commit:

- c7c06faf fix(customer-local): clarify wizard install and reset messaging

File changed:

- deploy/customer-local-template/base/frontend-dist/wizard_index.html

Scope:

- customer-facing text only;
- 11 insertions / 11 deletions;
- no changes to install.sh;
- no changes to wizard.py;
- no changes to preflight;
- no changes to Docker, DB, volumes, install mode, or runtime.

The wizard now distinguishes more clearly:

- Installa / aggiorna GreenBrain;
- Reset completo e reinstalla;
- compatible installs keep local data and secrets;
- reset complete removes and recreates the local database.

Validated markers:

- Installa / aggiorna GreenBrain
- Reset completo e reinstalla
- installazione compatibile
- dati locali e i segreti vengono mantenuti
- reset completo e reinstallare

Core wizard markers remained present:

- /api/install
- /api/status
- /api/log
- /api/local-credentials
- force_fresh_install
- LOCAL_DB_CREDENTIALS_FAILED
- INSTALL_EXIT_CODE=31
- freshResetBtn
- openBtn

### Preflight port wording

Commit:

- 953ff04d fix(customer-local): clarify preflight port messages

File changed:

- deploy/customer-local-template/base/scripts/preflight-local-install.sh

Scope:

- customer-facing text only inside check_port();
- 5 insertions / 5 deletions;
- no changes to conditions;
- no changes to ports;
- no changes to Docker;
- no changes to compose;
- no changes to DB;
- no changes to volumes;
- no changes to install mode.

Behavior preserved:

- existing GreenBrain stack on a port: warning and continue;
- external service on a port: error and exit 1;
- process listing via lsof remains;
- macOS/Windsurf guidance remains, now clearer in Italian.

Validated markers:

- Porta $port ($label) già usata da una installazione GreenBrain locale esistente
- aggiornamento/reinstallazione controllata
- porta $port ($label) già usata da un altro programma esterno a GreenBrain
- Programma che sta usando la porta $port
- chiudi Windsurf prima di installare GreenBrain

Logic anchors remained present:

- check_port()
- in_use=0
- gb_match=0
- exit 1
- LOCAL_BACKEND_PORT
- LOCAL_FRONTEND_PORT
- LOCAL_POSTGRES_PORT
- PREFLIGHT_LOCAL_INSTALL_OK

## Version bump

Commit:

- e5b10971 chore(customer-local): bump runtime template to 0.1.140

Changed files:

- deploy/customer-local-template/VERSION
- deploy/customer-local-template/release-manifest.yml

Version:

- VERSION: 0.1.140
- package_version: 0.1.140

## Release artifacts

Release directory:

- releases/customer-local/0.1.140

Build info:

- release_version=0.1.140
- built_at=2026-06-04T16:22:52Z
- git_commit=e5b1097193d9c1a991d8c040e2d85ec0b87e3931

Artifacts:

- BUILD-INFO.txt
- customer-local-0.1.140.tar.gz
- INSTALLA_GREENBRAIN.run
- GreenBrain-Installer.zip
- universal-installer/GreenBrain-Install.desktop
- universal-installer/INSTALLA_GREENBRAIN_LINUX.run
- universal-installer/INSTALLA_GREENBRAIN_MAC.command
- universal-installer/INSTALLA_GREENBRAIN_WINDOWS.bat
- universal-installer/INSTALLA_GREENBRAIN_WINDOWS.ps1
- universal-installer/LEGGIMI_INSTALLAZIONE.txt

Final SHA256:

- customer-local-0.1.140.tar.gz: 168ef3712075e39b99a1eaebcba3e3bd64fc811e392cf4189d68f90a8d1cb61d
- GreenBrain-Installer.zip: c4548d5827268338f4fac8f92655e0a925e4e44e3625e839a9cdac61a8ca13b0
- INSTALLA_GREENBRAIN.run: 553a91b716572cc398d3571bb6a9c179380641106551b975e3cfff636aa3e89b

## Packaging correction

During validation, the first 0.1.140 package build was found to have the wrong archive prefix:

- wrong: customer-local-template/...
- expected: package/customer-local-template/...

The package was rebuilt to match 0.1.139 and the validation scripts:

- package/customer-local-template/...

Final package-prefix rebuild result:

- CUSTOMER_LOCAL_0140_PACKAGE_PREFIX_REBUILD_OK version=0.1.140 commit=e5b1097193d9c1a991d8c040e2d85ec0b87e3931

Validated paths:

- package/customer-local-template/VERSION
- package/customer-local-template/base/frontend-dist/wizard_index.html
- package/customer-local-template/base/scripts/preflight-local-install.sh

## Static validation

Static validation passed after the package-prefix rebuild.

Results:

- CUSTOMER_LOCAL_RELEASE_STATIC_VALIDATION_OK version=0.1.140
- CUSTOMER_LOCAL_0140_STATIC_VALIDATION_WITH_UX_AND_ENV_OK

Validated:

- release directory;
- BUILD-INFO;
- tar payload;
- ZIP payload;
- VERSION/package_version;
- nginx proxy backend:8000;
- old host.docker.internal:8008 target absent;
- run-local backend markers;
- password sync DB markers;
- frontend markers;
- prebuilt compose has no build sections;
- wizard UX markers present;
- preflight UX markers present;
- excluded env files absent from tar and ZIP payload.

Explicitly excluded env files:

- backend-src/.env
- overlay/env/customer-local.env
- overlay/tunnel/cloudflared/cloudflared.env

## GHCR images

Images were retagged from 0.1.139 to 0.1.140 and pushed because this release did not change backend or ml-worker runtime image code.

Backend:

- ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.140
- digest sha256:5393a58cda52e2562340544f15fe64bd04ad9c76b2b0fe6aa6e957d7540a0655

ML worker:

- ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.140
- digest sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680

Image validation result:

- CUSTOMER_LOCAL_IMAGES_VALIDATION_OK version=0.1.140

Validated:

- backend image pull OK;
- ml-worker image pull OK;
- backend run-local/password-sync markers OK;
- backend runtime register markers OK;
- backend password seed markers OK;
- ml-worker basic smoke OK.

## Fresh personalized install validation

Fresh install validation passed for tenant z.

Result:

- CUSTOMER_LOCAL_FRESH_INSTALL_VALIDATION_OK version=0.1.140 tenant=z

Personalized bundle:

- GreenBrain-Installer-0.1.140-z-20260604163638.zip
- SHA256 e067314d170fa37578fe8231ff08fee34f5be18d9e525b2793784d78518b8c4c

Host-visible personalized tar:

- customer-local-0.1.140-z-20260604163637.tar.gz

Token hint:

- 6xczAo

Install path:

- /tmp/gb_validate_0_1_140_z_install_rskW46/package/customer-local-template

Installation id:

- 755d0862-aede-4a79-81f3-850dbd126772

Validated runtime:

- VERSION 0.1.140;
- package_version 0.1.140;
- backend image ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.140;
- ml-worker image ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.140;
- frontend proxy run-local HTTP 200 no_pending;
- direct backend run-local HTTP 200 no_pending;
- local login z@gmail.com HTTP 200;
- EXTENDED_DOCTOR_OK;
- RUN_LOCAL_DAILY_ONCE_OK;
- heartbeat sent successfully;
- installed_release_version 0.1.140;
- local_agent_version 0.1.140;
- runtime_health healthy.

Local seeded user:

- email: z@gmail.com
- password_version: 19
- password_change_source: cloud_seed
- password_last_sync_status: synced

## Known notes

Intentional untracked files remain outside release:

- docs/analysis/bundle_plugnplay_plan_20260521.md
- docs/analysis/exec_plan_0.1.122.md
- docs/analysis/report_0.1.122_20260520.md
- releases/customer-local-0.1.122.tar.gz

Do not include them unless explicitly intended.

## Recommended next priorities

### 0.1.141 — Token and installation cleanup tooling

Add a small admin/ops utility to:

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
