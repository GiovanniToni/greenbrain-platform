# GreenBrain Customer Local 0.1.146 — Status and Roadmap

Date: 2026-06-16  
Branch: `feat/customer-ops-supabase-foundation`  
Release version: `0.1.146`  
Release commit: `ca375cbf0a9bf1a0fcea10f0e2b6143b626b7bdf`

## Summary

Customer-local release `0.1.146` completes the Source DB guided setup and importer hardening work started after `0.1.145`.

The release is focused on making the Source DB integration safer and more operationally reliable:

- cloud customer portal can generate a DB-manager request template;
- cloud customer portal can parse the DB-manager response and prefill Source DB configuration safely;
- standard Source DB view alias is now `GREENBRAIN_VIEW_SALES_RAW`;
- Source DB technical check classifies errors with stable `failure_code`, `failure_message`, and `action_required`;
- source DB importer now supports both the standard alias view and the legacy `GREENHOUSE_VIEW_STAT` column shape;
- source DB importer dynamically introspects source columns and builds the SELECT query with safe aliases;
- source DB importer supports optional `movim_cassa` filtering only when the column exists;
- missing required source columns now fail with explicit `missing_import_required_columns`;
- normalized import payload now validates required destination fields with `missing_normalized_import_columns`;
- `source-db-importer` image remains a dedicated service and includes ODBC Driver 18 for SQL Server.

## Commits included after 0.1.145

- `25bcedc0` — `feat(customer-portal): add source db request parser endpoints`
- `4c4ed13a` — `feat(customer-portal): add source db frontend api client`
- `26575f2f` — `feat(customer-portal): guide source db setup flow`
- `7255a758` — `feat(customer-local): classify source db technical check failures`
- `7b463417` — `fix(customer-local): default source db view to standard alias`
- `2b7a9a89` — `fix(customer-local): support standard source db import view`
- `ca375cbf` — `chore(customer-local): bump runtime template to 0.1.146`

## Release artifacts

Directory:

`/opt/greenbrain-platform/releases/customer-local/0.1.146/`

Artifacts:

- `BUILD-INFO.txt`
- `customer-local-0.1.146.tar.gz`
- `INSTALLA_GREENBRAIN.run`
- `GreenBrain-Installer.zip`
- `universal-installer/INSTALLA_GREENBRAIN_LINUX.run`
- `universal-installer/INSTALLA_GREENBRAIN_MAC.command`
- `universal-installer/INSTALLA_GREENBRAIN_WINDOWS.bat`
- `universal-installer/INSTALLA_GREENBRAIN_WINDOWS.ps1`
- `universal-installer/LEGGIMI_INSTALLAZIONE.txt`

Artifact SHA256:

- `BUILD-INFO.txt`: `114a4a54c85249b135001f05cc439faf4b0a357b18a4938b6a74a5aac2864413`
- `customer-local-0.1.146.tar.gz`: `603cda235db433d54c9ee0df0911c563ad2cbb440cff8a24a2524fa7606dd1a2`
- `INSTALLA_GREENBRAIN.run`: `022caa73f130d42f2e4967725dcf80922636c7ad670a0cc0e44abca14827310f`
- `GreenBrain-Installer.zip`: `ebb51bff8687fdf88d4f2f1d5c422d24c4934aa63f38312f413cba888abfb86a`

## GHCR images

- `ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.146`
  - digest: `sha256:bec942304ed9ded6a8573ab1e762a61ae8abb665c63d00f2930249c70af26976`
- `ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.146`
  - digest: `sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680`
- `ghcr.io/giovannitoni/greenbrain-customer-source-db-importer:0.1.146`
  - digest: `sha256:48b64c7f51c0923851d07b38e9b274b44b6039d1658c9f9e38df56e51342f672`

## Validations completed

### Static release validation

Passed:

`CUSTOMER_LOCAL_RELEASE_STATIC_VALIDATION_OK version=0.1.146`

Validated:

- release directory and root artifacts;
- `BUILD-INFO.txt` version and commit;
- TAR payload version and manifest;
- core runtime files;
- nginx proxy target `backend:8000`;
- no old `host.docker.internal:8008` proxy;
- password sync local route markers;
- frontend password sync/download markers;
- Source DB technical flow scripts and upload markers;
- prebuilt compose has no `build:` sections;
- GHCR image references for backend, ML worker, and source-db-importer;
- universal ZIP structure;
- embedded ZIP payload version and Source DB technical flow.

### Image validation

Passed:

`IMAGE_PUSH_OK`

`SOURCE_DB_IMPORTER_PUSHED_IMAGE_SMOKE_OK`

Validated:

- backend image pushed and pull-verified;
- ml-worker image pushed and pull-verified;
- source-db-importer image pushed and pull-verified;
- source-db-importer image includes `ODBC Driver 18 for SQL Server`.

### Fresh install validation

Passed:

`CUSTOMER_LOCAL_FRESH_INSTALL_VALIDATION_OK version=0.1.146 tenant=z`

`CUSTOMER_LOCAL_0_1_146_FRESH_INSTALL_VALIDATION_68E_OK`

Fresh install facts:

- tenant: `z`
- email: `z@gmail.com`
- personalized bundle: `GreenBrain-Installer-0.1.146-z-20260616081622.zip`
- personalized ZIP SHA256: `89c4359bf4af052e0a3964bcf3d95274cf0e54c86bec5b76f2997264f68d398c`
- local install path: `/tmp/gb_validate_0_1_146_z_install_huY3Tv/package/customer-local-template`
- installation id: `59f1234b-f79d-4880-a07b-9a4aeed340da`
- provisioning token hint: `Q0mTio`
- install exit code: `0`
- backend image: `ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.146`
- ml-worker image: `ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.146`
- source-db-importer image: `ghcr.io/giovannitoni/greenbrain-customer-source-db-importer:0.1.146`
- local user provisioning: `LOCAL_USER_PROVISION_OK`
- local DB credentials: `LOCAL_DB_CREDENTIALS_OK`
- backend health: OK
- frontend health: OK
- local login: HTTP 200
- password sync run-local route: HTTP 200, `no_pending`
- extended doctor: `EXTENDED_DOCTOR_OK`
- daily run: `RUN_LOCAL_DAILY_ONCE_OK`
- Source DB import: skipped cleanly as not configured
- heartbeat: HTTP 200, runtime healthy, installed/local agent version `0.1.146`

### Cleanup

Fresh install test runtime cleaned successfully:

`CUSTOMER_LOCAL_0_1_146_FRESH_INSTALL_CLEANUP_68E_BIS_OK`

## Known notes

- Source DB configuration is intentionally optional at install time.
- If `source-db.env` is not configured, local daily sequence skips Source DB import cleanly with `SOURCE_DB_IMPORT_NOT_CONFIGURED`.
- The preferred source view is now `GREENBRAIN_VIEW_SALES_RAW`.
- Legacy `GREENHOUSE_VIEW_STAT` remains supported by dynamic importer mapping.
- Local staging destination still uses `imponibilenetto` internally for compatibility with existing local schema.

## Roadmap after 0.1.146

Recommended next steps:

1. Run a real Mac update/install test with the 0.1.146 personalized bundle.
2. Test Source DB technical check against a real SQL Server/Greenhouse DB with `GREENBRAIN_VIEW_SALES_RAW`.
3. Test Source DB import against:
   - standard alias view;
   - legacy view;
   - missing optional `movim_cassa`;
   - missing required columns.
4. Add user-facing Source DB technical check result display in the customer portal if not already sufficient.
5. Consider making the root `INSTALLA_GREENBRAIN.run` alias generation part of `build_customer_local_universal_installer.sh` so it is not required as a manual release step.
6. After docs commit, tag release as `customer-local-0.1.146`.
