# GreenBrain Customer Local — Status and Roadmap 0.1.142

Date: 2026-06-05
Release version: 0.1.142
Branch: feat/customer-ops-supabase-foundation

## Release purpose

0.1.142 is a small customer-local UX release focused on password visibility.

The goal is to let users reveal/hide password text wherever a password must be typed, avoiding mistakes caused by masked-only password fields.

## Included commits

### Password visibility toggles

Commit:

- 03905ee8 feat(frontend): add password visibility toggles

Scope:

- apps/frontend/src/components/PasswordInput.tsx
- apps/frontend/src/pages/Login.tsx
- apps/frontend/src/pages/Signup.tsx
- apps/frontend/src/pages/CustomerOpsConsolePage.tsx
- apps/frontend/src/pages/CustomerPortalDashboard.tsx
- deploy/customer-local-template/base/frontend-dist/wizard_index.html

Coverage:

- Login password field
- Signup portal password field
- Ops temporary admin password field
- Customer account security tab:
  - current password
  - new password
  - confirm new password
- Customer-local installer wizard:
  - customer_password
  - postgres_password
  - sql_pass

Safety:

- UI-only change
- no backend changes
- no API changes
- no database migrations
- no token/provisioning changes
- no auth/password-sync logic changes
- no install-flow logic changes

### Version bump

Commit:

- 4294333c chore(customer-local): bump runtime template to 0.1.142

Changed files:

- deploy/customer-local-template/VERSION
- deploy/customer-local-template/release-manifest.yml

Version:

- VERSION: 0.1.142
- package_version: 0.1.142

## Build artifacts

Release directory:

- releases/customer-local/0.1.142

Artifacts:

- customer-local-0.1.142.tar.gz
- GreenBrain-Installer.zip
- INSTALLA_GREENBRAIN.run
- BUILD-INFO.txt

BUILD-INFO:

- release_version=0.1.142
- git_commit=4294333c86dc623477778d67ae2a2c7916d198ba
- built_at=2026-06-05T09:00:44Z

Artifact SHA256:

- customer-local-0.1.142.tar.gz: a6ae9076f45f70c101581622d1eee8da1f983553af1a2e5d8093c8c1f7db3e82
- GreenBrain-Installer.zip: ee8c31734ac754724bcc0c968170013931a0c464c59e496b6ced8bde964a2f04
- INSTALLA_GREENBRAIN.run: cf589d90ea734aa7d12661de6e67c8671fb4010211bb5b5a34f48955b1f1e02c

## Static validation

Primary static validation passed:

- CUSTOMER_LOCAL_RELEASE_STATIC_VALIDATION_OK version=0.1.142

Password visibility artifact validation passed:

- CUSTOMER_LOCAL_0142_PASSWORD_VISIBILITY_ARTIFACT_VALIDATION_FIXED_OK
- TAR_PASSWORD_VISIBILITY_COUNTS_OK
- ZIP_PASSWORD_VISIBILITY_COUNTS_OK
- ROOT_RUN_PASSWORD_VISIBILITY_COUNTS_OK

Confirmed password visibility markers inside:

- customer-local-0.1.142.tar.gz
- GreenBrain-Installer.zip
- INSTALLA_GREENBRAIN.run

Expected wizard counts:

- button_toggles: 3
- function_toggle: 1
- password_wraps: 3
- password_toggle_buttons: 3
- customer_password_ids: 1
- postgres_password_ids: 1
- sql_pass_ids: 1

## GHCR images

0.1.142 images were retagged from 0.1.140 because this release did not change backend or ML worker runtime code.

Backend image:

- ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.142
- digest: sha256:5393a58cda52e2562340544f15fe64bd04ad9c76b2b0fe6aa6e957d7540a0655
- image id: sha256:e1a772b44385c375d522b6097c3018f233e4d0b44ea43d698acfdb6ed8600ba4

ML worker image:

- ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.142
- digest: sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680
- image id: sha256:53b9c4a1417641773eb44650eb84d39b56a2734600d54586dc2f6a92c88ba9f7

Image validation passed:

- CUSTOMER_LOCAL_IMAGES_VALIDATION_OK version=0.1.142
- CUSTOMER_LOCAL_0142_IMAGES_VALIDATED_OK

## Fresh install validation

Fresh personalized install validation passed for tenant z:

- CUSTOMER_LOCAL_FRESH_INSTALL_VALIDATION_OK version=0.1.142 tenant=z
- CUSTOMER_LOCAL_0142_FRESH_INSTALL_VALIDATED_OK

Validation parameters:

- tenant: z
- email: z@gmail.com
- password length: 9
- personalized ZIP: GreenBrain-Installer-0.1.142-z-20260605091504.zip
- personalized ZIP SHA256: c4e3670489ddc0c0c038bd707935edf4df1b1db614a59eeff498eb220789496a
- token hint: RG2yYw
- install path: /tmp/gb_validate_0_1_142_z_install_0TEjap/package/customer-local-template
- installation id: 290b95c3-5803-4b0d-a2e9-6a9c5a8d5fa5

Fresh install confirmed:

- central runtime register OK
- provisioning OK
- Docker image tag 0.1.142
- prebuilt Docker images used
- backend healthy
- frontend healthy
- local user provisioned
- password metadata seeded from cloud
- local password sync status synced
- local login OK
- run-local password sync returned no_pending
- doctor OK
- extended doctor OK
- run-local-daily-once OK
- heartbeat sent and accepted
- cloud installation healthy with installed_release_version/local_agent_version 0.1.142

## Current release state

0.1.142 is validated and ready to publish/tag.

It supersedes 0.1.141 for customer-facing installer downloads because 0.1.141 did not include the password visibility UX changes.

## Recommended next steps

1. Commit this status document.
2. Tag customer-local-0.1.142 on bump commit 4294333c86dc623477778d67ae2a2c7916d198ba.
3. Push branch and tag.
4. Optional real-browser check:
   - download latest installer from /account
   - confirm filename is 0.1.142
   - open wizard and visually confirm Mostra/Nascondi on all password fields.
