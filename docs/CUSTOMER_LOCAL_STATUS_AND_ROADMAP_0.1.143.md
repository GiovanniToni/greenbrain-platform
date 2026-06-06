# GreenBrain Customer Local 0.1.143 — Status and Roadmap

Date: 2026-06-06  
Branch: feat/customer-ops-supabase-foundation  
Release tag target commit: `2a629148aebe6e9efe2c1a38db262163ac37f81c`

## Summary

Customer-local 0.1.143 promotes the latest cloud/backend/frontend work into the customer-local template and release bundle. The release includes the password reset self-service/customer-ops milestone, internal security alerts, admin notification bell integration, manual reset-link tracking, and password-reset completion history.

## Included changes since 0.1.142

Main commits included:

- `ff642404` feat(customer-ops): show security alerts in admin notification bell
- `2f19e78a` feat(customer-ops): track manually sent password reset links
- `3cb8bdcd` feat(customer-ops): show password reset completion history
- `cf449dff` feat(customer-ops): create alert for admin-sent reset links
- `1e0d5a15` chore(customer-local): promote template to 0.1.143
- `2a629148` fix(customer-local): keep installer wizard index in 0.1.143

## Password reset/customer-ops behavior

Validated behavior:

1. Customer starts forgot-password from the public UI.
2. Backend keeps anti-enumeration generic public response.
3. A customer security alert is created for admin/customer-ops visibility.
4. Admin notification bell shows the active alert.
5. CustomerDetail shows the password-reset alert.
6. Admin can generate a reset link.
7. After copying the link, admin can mark the link as sent.
8. The alert changes to `email_sent`, remains active, and stays visible in the notification bell.
9. The alert is resolved automatically only when the customer completes the reset.
10. CustomerDetail keeps password reset completion history:
    - last reset timestamp
    - password version
    - local password sync status
    - local sync timestamp

Also validated:

- Admin can generate and send a reset link even without a prior customer forgot-password request.
- In that case, an `admin_manual` / `email_sent` alert is created and remains active until reset completion.

## Release artifacts

Release directory:

`/opt/greenbrain-platform/releases/customer-local/0.1.143/`

Generated artifacts:

- `customer-local-0.1.143.tar.gz`
- `INSTALLA_GREENBRAIN.run`
- `GreenBrain-Installer.zip`
- `BUILD-INFO.txt`
- `package/customer-local-template`
- `universal-installer/*`

`BUILD-INFO.txt`:

- release_version: `0.1.143`
- git_commit: `2a629148aebe6e9efe2c1a38db262163ac37f81c`

## GHCR images

Validated images:

- `ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.143`
  - digest: `sha256:860c07462e26ad994fbcc1f63e8dac9ab4403a163a3cb2a7bd66feaef0aef70e`
- `ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.143`
  - digest: `sha256:bfca7b294dfd992b4426d242d7a5c975717d17b1a377c6b80d5548fc306ec680`

The backend image is new for 0.1.143 and includes the promoted password reset/customer-ops backend code. The ML worker image is unchanged, as expected.

## Validations

### Static release validation

Passed:

`CUSTOMER_LOCAL_RELEASE_STATIC_VALIDATION_OK version=0.1.143`

Validation confirmed:

- release files exist
- version/package_version are 0.1.143
- `frontend-dist/index.html` exists
- `frontend-dist/wizard_index.html` exists
- nginx local proxy uses `backend:8000`
- old `host.docker.internal:8008` proxy target absent
- universal installer ZIP structure valid
- embedded ZIP payload version/package_version valid

### Image validation

Passed:

`CUSTOMER_LOCAL_IMAGES_VALIDATION_OK version=0.1.143`

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

`CUSTOMER_LOCAL_FRESH_INSTALL_VALIDATION_OK version=0.1.143 tenant=z`

Validation details:

- personalized portal download OK
- bundle SHA256 OK
- host-visible personalized ZIP/TAR generated
- fresh install completed with `INSTALL_RC=0`
- runtime installation id: `b80dee37-afc4-46c1-b32e-9189dc7f2514`
- Docker image tag: `0.1.143`
- backend image: `ghcr.io/giovannitoni/greenbrain-customer-backend:0.1.143`
- ml-worker image: `ghcr.io/giovannitoni/greenbrain-customer-ml-worker:0.1.143`
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
- cloud heartbeat shows installed/local_agent version 0.1.143

## Notes

The installer wizard file `base/frontend-dist/wizard_index.html` is still required by:

- `base/apps/local-installer-wizard/wizard.py`
- `tools/validation/validate_customer_local_release.sh`

It was restored from 0.1.142 after promote and included in the 0.1.143 template.

## Remaining untracked files intentionally not included

- `docs/analysis/bundle_plugnplay_plan_20260521.md`
- `docs/analysis/exec_plan_0.1.122.md`
- `docs/analysis/report_0.1.122_20260520.md`
- `releases/customer-local-0.1.122.tar.gz`

## Next recommended phase

- Add Resend transactional email for automatic self-service password reset email delivery.
- Keep admin external notifications limited to relevant failures/abuse/bounces.
- Add bounce/failure alert states when email delivery is introduced.
- Preserve the current manual fallback flow.
