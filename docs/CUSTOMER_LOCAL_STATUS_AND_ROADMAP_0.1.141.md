# GreenBrain Customer Local — Status and Roadmap 0.1.141

Date: 2026-06-05
Release version: 0.1.141
Branch: feat/customer-ops-supabase-foundation

## Release purpose

0.1.141 is a tools-only and read-only operational milestone.

It does not introduce customer-local runtime behavior changes, installer changes, database migrations, token mutations, or installation archival logic.

The release adds a safe ops utility to inspect customer-local runtime provisioning tokens and installation records after the long install/password-sync/release validation cycle.

## Included commits

### Read-only runtime admin utility

Commit:

- c05c502c tools(customer-local): add read-only runtime admin utility

File:

- tools/ops/customer_local_runtime_admin.py

Commands added:

- summary
- list-tokens
- list-installations

Purpose:

- inspect tenant runtime provisioning tokens;
- inspect tenant runtime installations;
- show latest installation by heartbeat;
- show latest token by creation time;
- expose safe JSON output for ops review.

Safety:

- read-only mode only;
- no UPDATE;
- no DELETE;
- no INSERT;
- no TRUNCATE;
- no DROP;
- no ALTER;
- no token hash exposure;
- unsupported mutation flags are rejected.

### Read-only cleanup plan

Commit:

- 87afeb03 tools(customer-local): add read-only cleanup plan

File:

- tools/ops/customer_local_runtime_admin.py

Command added:

- cleanup-plan

Purpose:

- compute a plan-only view of old healthy runtime installations;
- identify the latest healthy installation to keep;
- list old healthy installation candidates for future review;
- report active token warnings;
- report token status counts;
- report schema limitations before any cleanup implementation.

Safety:

- plan_only true;
- mutations_enabled false;
- updates 0;
- deletes 0;
- revokes 0;
- archives 0;
- token_hash_exposed false.

## Version bump

Commit:

- b60d9010 chore(customer-local): bump runtime template to 0.1.141

Changed files:

- deploy/customer-local-template/VERSION
- deploy/customer-local-template/release-manifest.yml

Version:

- VERSION: 0.1.141
- package_version: 0.1.141

## Final validation

Validation result:

- CUSTOMER_LOCAL_0141_READONLY_TOOLS_FINAL_VALIDATION_OK

Validated commands:

- summary
- list-tokens
- list-installations
- cleanup-plan

Static checks:

- PY_COMPILE_OK
- NO_MUTATION_PATTERNS_FOUND_OK

Runtime smoke via dev_backend:

- summary --tenant z OK
- cleanup-plan --tenant z --keep-latest-healthy 1 --limit-candidates 5 OK

## Tenant z observed state

Latest healthy installation:

- installation_id: 755d0862-aede-4a79-81f3-850dbd126772
- installed_release_version: 0.1.140
- local_agent_version: 0.1.140
- provisioning_status: active
- runtime_health: healthy

Latest token:

- token_hint: 6xczAo
- status: used
- used_by_installation_id: 755d0862-aede-4a79-81f3-850dbd126772

Token status counts:

- revoked: 94
- used: 11
- active: 0

Cleanup-plan result:

- keep latest healthy installation: 755d0862-aede-4a79-81f3-850dbd126772
- active token count: 0
- candidate old installations returned for review
- no database mutation performed

## Schema decision

The schema analysis found no archive-like columns on the runtime token or runtime installation tables.

Tables inspected:

- gb_customer_runtime_provisioning_tokens
- gb_customer_runtime_installations

No columns found like:

- archived
- archived_at
- deleted
- retired
- inactive

Therefore 0.1.141 intentionally does not implement real archive/revoke cleanup actions.

Any future cleanup mutation should first add explicit schema support, such as:

- archived_at
- archived_by
- archive_reason
- retired_at
- retired_by
- retired_reason

## What this release does not do

0.1.141 does not:

- revoke tokens;
- archive installations;
- delete records;
- mutate database rows;
- add migrations;
- change customer-local installer behavior;
- change runtime heartbeat behavior;
- change password sync behavior;
- change frontend customer UX;
- build or publish a new customer installer package.

## Recommended next priorities

### Option A — Close 0.1.141 as tools-only milestone

Recommended.

Use 0.1.141 to mark the safe operational tooling milestone, then proceed to future work only after review.

### Option B — Future schema-backed cleanup

Only later, add explicit archive/retire columns and keep cleanup mutations behind strict guards:

- --apply required;
- --tenant required;
- --confirm-tenant required;
- --confirm-action required;
- no hard deletes;
- audit trail required.

### Option C — Product/account UX

After ops cleanup safety, continue with /account maturity:

- installed/downloaded/available version;
- local/cloud password status;
- last heartbeat;
- open runtime button;
- download update button;
- sync password button.
