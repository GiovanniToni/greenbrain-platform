# Wave 1 Runbook
> Repo canonicalization and documentation. Zero runtime changes.
> Generated: 2026-03-27. All steps are safe to run while all services are live.

---

## Objective

Structure the monorepo correctly: SQL files in place, `.gitignore` protecting binary artifacts, stale `.bak` files removed, systemd units consolidated, old docs archived. No service is restarted. No code is changed.

---

## Preconditions

```bash
# All 6 systemd timers must be active:
systemctl list-timers --all | grep gh- | wc -l
# Expected: 6

# All 6 Docker containers must be running:
docker ps --format "{{.Names}}: {{.Status}}" | grep gb_v2 | wc -l
# Expected: 6

# DATABASE_URL must resolve to Supabase (not local Docker):
source /opt/greenbrain-platform/infra/scripts/load_env.sh
psql "$DATABASE_URL" -c "SELECT COUNT(*) FROM cron.job;"
# Expected: a row count (10). If this errors, do not proceed — schema export will fail.

# No Wave 1 should change .bak_phase* files — confirm they exist for Wave 4:
find /opt/greenbrain-platform/apps/ml-worker -name "*.bak_phase*" | wc -l
# Expected: 7 (these are Wave 4 files — do NOT touch them in this wave)
```

---

## Step-by-step commands

---

### Step 1 — Export Supabase schema snapshot

**Purpose:** Create a versioned, source-controlled snapshot of the live Supabase schema. `sql/schema/current-schema.sql` already exists (local Docker dump from `gb_v2_postgres`). The new file `supabase-schema.sql` is the Supabase cloud truth.

```bash
source /opt/greenbrain-platform/infra/scripts/load_env.sh

pg_dump "$DATABASE_URL" \
  --schema-only \
  --no-owner \
  --no-acl \
  --file /opt/greenbrain-platform/sql/schema/supabase-schema.sql
```

**Expected result:** Command exits silently (no output = success).

```bash
# Verify the file was created and is non-trivial:
wc -l /opt/greenbrain-platform/sql/schema/supabase-schema.sql
# Expected: > 1000 lines

ls -lh /opt/greenbrain-platform/sql/schema/
# Expected: two files — current-schema.sql (local Docker) and supabase-schema.sql (Supabase)
```

**If `pg_dump` errors with "connection refused" or auth error:**
- Verify `DATABASE_URL` points to Supabase: `echo $DATABASE_URL | cut -c1-40`
- It must start with `postgres://` and contain `pooler.supabase.com`
- Check credentials in `infra/env/dev.env`

**If file is < 100 lines:** The export was empty or truncated. Check `pg_dump` error output. Do not proceed.

---

### Step 2 — Populate sql/migrations/

**Purpose:** Move the 8 migration SQL files from their misplaced location (`jobs/migrations/`) into `sql/migrations/` with sequential numeric prefixes. The `sql/migrations/` directory already exists but is empty.

```bash
SRC=/opt/greenbrain-platform/apps/ml-worker/jobs/migrations
DST=/opt/greenbrain-platform/sql/migrations

# Verify source files:
ls "$SRC"
# Expected: 8 blocco_*.sql files:
#   blocco_a_migration.sql  blocco_b_migration.sql  blocco_c_migration.sql
#   blocco_c1_migration.sql blocco_d_migration.sql  blocco_d1_migration.sql
#   blocco_f_migration.sql  blocco_g_migration.sql

# Copy with sequential prefix (a→001, b→002, c→003, c1→004, d→005, d1→006, f→007, g→008):
cp "$SRC/blocco_a_migration.sql"  "$DST/001_blocco_a.sql"
cp "$SRC/blocco_b_migration.sql"  "$DST/002_blocco_b.sql"
cp "$SRC/blocco_c_migration.sql"  "$DST/003_blocco_c.sql"
cp "$SRC/blocco_c1_migration.sql" "$DST/004_blocco_c1.sql"
cp "$SRC/blocco_d_migration.sql"  "$DST/005_blocco_d.sql"
cp "$SRC/blocco_d1_migration.sql" "$DST/006_blocco_d1.sql"
cp "$SRC/blocco_f_migration.sql"  "$DST/007_blocco_f.sql"
cp "$SRC/blocco_g_migration.sql"  "$DST/008_blocco_g.sql"
```

**Expected result:** 8 files in `sql/migrations/`.

```bash
ls /opt/greenbrain-platform/sql/migrations/ | wc -l
# Expected: 8
```

**If source file is missing:** Check the exact filename: `ls "$SRC"`. Adjust the cp command. Do not guess names.

**Note:** These are `cp`, not `mv`. The originals in `jobs/migrations/` remain until Wave 3 cleanup. Do not delete them now.

---

### Step 3 — Write sql/cron/pg_cron_canonical.sql

**Purpose:** Create a version-controlled SQL file that defines the 10 intended pg_cron jobs. Generated directly from the live Supabase DB to guarantee accuracy.

```bash
source /opt/greenbrain-platform/infra/scripts/load_env.sh

# Generate the canonical file from the live cron.job table:
psql "$DATABASE_URL" -P pager=off -t -c "
SELECT
  '-- Job ' || jobid || ': ' || jobname || E'\n' ||
  'SELECT cron.schedule(' ||
    quote_literal(jobname) || ', ' ||
    quote_literal(schedule) || ', ' ||
    '\$\$' || command || '\$\$' ||
  ');' || E'\n'
FROM cron.job
ORDER BY jobid;
" > /opt/greenbrain-platform/sql/cron/pg_cron_canonical.sql
```

**Prepend a header:**
```bash
cat > /tmp/cron_header.sql << 'EOF'
-- pg_cron Canonical Job Definitions
-- Source: Supabase cron.job table (10 active jobs as of Wave 0 completion)
-- Jobs 30, 38, 39 were removed in Wave 0 (every-minute ETL overcall).
-- To apply: run each SELECT cron.schedule(...) against the Supabase DB.
-- Do NOT apply against local Docker PostgreSQL.

EOF
cat /tmp/cron_header.sql /opt/greenbrain-platform/sql/cron/pg_cron_canonical.sql \
  > /tmp/pg_cron_final.sql
mv /tmp/pg_cron_final.sql /opt/greenbrain-platform/sql/cron/pg_cron_canonical.sql
```

**Expected result:**

```bash
wc -l /opt/greenbrain-platform/sql/cron/pg_cron_canonical.sql
# Expected: > 20 lines

grep "cron.schedule" /opt/greenbrain-platform/sql/cron/pg_cron_canonical.sql | wc -l
# Expected: 10
```

**If count is not 10:** Re-run the psql query interactively to check what `cron.job` returns:
```bash
psql "$DATABASE_URL" -c "SELECT COUNT(*) FROM cron.job;"
```
Wave 0 must be complete (10 jobs) before this step.

---

### Step 4 — Write sql/README.md

**Purpose:** Document the purpose of each `sql/` subdirectory so the intent is clear.

```bash
cat > /opt/greenbrain-platform/sql/README.md << 'EOF'
# SQL Directory

## schema/
Point-in-time schema snapshots. Not the live source of truth — the live DB is.

- `supabase-schema.sql` — exported from Supabase cloud (run `pg_dump` to refresh)
- `current-schema.sql` — exported from local Docker `gb_v2_postgres` (may drift from Supabase)

To refresh the Supabase snapshot:
```bash
source infra/scripts/load_env.sh
pg_dump "$DATABASE_URL" --schema-only --no-owner --no-acl \
  -f sql/schema/supabase-schema.sql
```

## migrations/
Historical migration files (001–008), already applied to the live DB.
Do not re-apply. Use as reference for schema evolution history.

To apply to a fresh DB:
```bash
source infra/scripts/load_env.sh
bash sql/migrate.sh
```

## cron/
Canonical pg_cron job definitions.
- `pg_cron_canonical.sql` — the 10 intended jobs; apply only to Supabase, never to local Docker.

## diagnostics/
Ad-hoc diagnostic SQL. Not production code.
EOF
```

**Expected result:**

```bash
wc -l /opt/greenbrain-platform/sql/README.md
# Expected: > 25 lines
```

---

### Step 5 — Update .gitignore

**Purpose:** Prevent binary caches, model bundles, priors, and `.bak_phase*` migration artifacts from being committed accidentally.

```bash
GITIGNORE=/opt/greenbrain-platform/.gitignore
```

First, check what is already in `.gitignore` to avoid duplicates:
```bash
cat "$GITIGNORE" 2>/dev/null || echo "(file does not exist — will be created)"
```

Append the missing entries:
```bash
cat >> "$GITIGNORE" << 'EOF'

# ML binary caches and artifacts (Wave 1)
parquet_cache/
priors_cache/
models_v4/
models_v4_backup/

# Migration artifacts (keep .bak_phase* files tracked until Wave 4 applies them)
*.bak
*.bak_[0-9]*
__pycache__/
*.pyc
*.pyo

# Env files (never commit live secrets)
apps/frontend/.env
apps/backend/.env
infra/docker/.env
infra/env/*.secret

# Editor artifacts
.DS_Store
*.swp
EOF
```

**Expected result:**

```bash
grep "parquet_cache" "$GITIGNORE"
grep "bak_phase" "$GITIGNORE" || echo "(bak_phase not blocked — these are tracked for Wave 4)"
# Confirm: *.bak_phase* should NOT be in .gitignore — they must remain visible for Wave 4
```

**Important:** Do NOT add `*.bak_phase*` to `.gitignore`. Those 7 files in `apps/ml-worker/` are the Wave 4 migration payloads and must remain tracked.

---

### Step 6 — Delete .bak files from /etc/systemd/system/

**Purpose:** Remove 9 stale backup files from `/etc/systemd/system/`. They are not loaded by systemd and clutter the directory.

```bash
# List before deleting (confirm the list):
find /etc/systemd/system -name "gh-*.bak*" -o -name "gh-*.bak.*"
```

**Expected list (9 files):**
```
/etc/systemd/system/gh-train-missing.timer.bak_20260310_103347
/etc/systemd/system/gh-train-missing.service.bak_20260327_124210
/etc/systemd/system/gh-refresh-registry.service.bak_20260327_123412
/etc/systemd/system/gh-parquet-export.service.bak_20260327_140708
/etc/systemd/system/gh-predict-all.service.bak_20260327_124638
/etc/systemd/system/gh-predict-all.timer.bak_20260310_103358
/etc/systemd/system/gh-train-missing.timer.bak_20260310_103358
/etc/systemd/system/gh-train-quarterly.service.bak.20260306_131008
/etc/systemd/system/gh-predict-all.timer.bak_20260310_103353
```

**If the list matches, delete:**
```bash
find /etc/systemd/system -name "gh-*.bak*" -o -name "gh-*.bak.*" | \
  xargs rm -f
```

**Verify:**
```bash
find /etc/systemd/system -name "gh-*.bak*" -o -name "gh-*.bak.*"
# Expected: no output
```

**If unexpected files appear in the list:** Do not delete blindly. Inspect each one: confirm it ends in `.bak*` or `.bak.*` and is not a live unit file. Live unit files end in `.service` or `.timer` with no suffix.

**No systemd reload needed** — `.bak*` files are not loaded by systemd.

---

### Step 7 — Delete .bak files from apps/backend/

**Purpose:** Remove 2 migration artifact files from the monorepo backend. These are not imported by any code.

```bash
# Confirm before deleting:
find /opt/greenbrain-platform/apps/backend -name "*.bak*"
# Expected:
#   /opt/greenbrain-platform/apps/backend/app/core/config.py.bak
#   /opt/greenbrain-platform/apps/backend/app/api/v1/ops.py.bak
```

**If list matches:**
```bash
rm /opt/greenbrain-platform/apps/backend/app/core/config.py.bak
rm /opt/greenbrain-platform/apps/backend/app/api/v1/ops.py.bak
```

**Verify:**
```bash
find /opt/greenbrain-platform/apps/backend -name "*.bak*"
# Expected: no output
```

**If additional `.bak` files appear:** Inspect each. Remove only if they are not Wave 4 files (`.bak_phase*`).

---

### Step 8 — Delete .bak files from infra/systemd/current/

**Purpose:** Clean the stale backup files inside the `current/` subdirectory before flattening.

```bash
# Confirm the bak files inside current/:
find /opt/greenbrain-platform/infra/systemd/current -name "*.bak*"
# Expected:
#   .../infra/systemd/current/gh-predict-all.timer.bak_20260310_103353
#   .../infra/systemd/current/gh-predict-all.timer.bak_20260310_103358
#   .../infra/systemd/current/gh-train-missing.timer.bak_20260310_103347
#   .../infra/systemd/current/gh-train-missing.timer.bak_20260310_103358
```

**Delete:**
```bash
find /opt/greenbrain-platform/infra/systemd/current -name "*.bak*" | xargs rm -f
```

**Verify:**
```bash
find /opt/greenbrain-platform/infra/systemd/current -name "*.bak*"
# Expected: no output
```

---

### Step 9 — Flatten infra/systemd/ using the next/ directory

**Purpose:** Move the 12 unit files to `infra/systemd/` directly (no subdirectory). Use `infra/systemd/next/` as the source — it has all 12 clean files including `gh-train-quarterly.timer` which is missing from `current/`.

```bash
# Verify next/ has all 12 expected files:
ls /opt/greenbrain-platform/infra/systemd/next/ | sort
```

**Expected (12 files):**
```
gh-parquet-export.service
gh-parquet-export.timer
gh-predict-all.service
gh-predict-all.timer
gh-refresh-registry.service
gh-refresh-registry.timer
gh-train-biweekly-all.service
gh-train-biweekly-all.timer
gh-train-missing.service
gh-train-missing.timer
gh-train-quarterly.service
gh-train-quarterly.timer
```

**If count is not 12:** Do not proceed. Identify the missing files and copy them from `/etc/systemd/system/`.

**If all 12 present, move to root:**
```bash
cd /opt/greenbrain-platform/infra/systemd/

# Copy all unit files from next/ to the root:
cp next/*.service .
cp next/*.timer .

# Verify 12 files at root:
ls *.service *.timer | wc -l
# Expected: 12
```

**Remove the now-redundant subdirectories:**
```bash
rm -rf /opt/greenbrain-platform/infra/systemd/current/
rm -rf /opt/greenbrain-platform/infra/systemd/next/
```

**Verify final state:**
```bash
ls /opt/greenbrain-platform/infra/systemd/
# Expected: 12 unit files and install.sh (after Step 10)
# Must NOT contain: current/, next/, or any .bak files
```

---

### Step 10 — Write infra/systemd/install.sh

**Purpose:** Create a repeatable deploy script that copies unit files from the monorepo to `/etc/systemd/system/` and runs `daemon-reload`.

```bash
cat > /opt/greenbrain-platform/infra/systemd/install.sh << 'SCRIPT'
#!/bin/bash
# Install systemd unit files from this directory to /etc/systemd/system/
# Usage: sudo bash infra/systemd/install.sh
set -e

UNIT_DIR=/etc/systemd/system
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing units from $SRC_DIR to $UNIT_DIR ..."
cp "$SRC_DIR"/*.service "$UNIT_DIR/"
cp "$SRC_DIR"/*.timer "$UNIT_DIR/"

systemctl daemon-reload
echo "Done. Installed $(ls "$SRC_DIR"/*.service "$SRC_DIR"/*.timer | wc -l) unit files."
SCRIPT

chmod +x /opt/greenbrain-platform/infra/systemd/install.sh
```

**Expected result:**
```bash
ls -l /opt/greenbrain-platform/infra/systemd/install.sh
# Expected: -rwxr-xr-x ... install.sh

head -5 /opt/greenbrain-platform/infra/systemd/install.sh
# Expected: first 5 lines of the script shown above
```

---

### Step 11 — Archive greenbrain-v2/docs/

**Purpose:** Preserve old architecture docs in the monorepo as a reference without polluting the active `docs/` tree.

```bash
# Create archive target:
mkdir -p /opt/greenbrain-platform/docs/archive/greenbrain-v2

# Copy (not move — preserve original for now):
cp -r /opt/greenbrain-v2/docs/. /opt/greenbrain-platform/docs/archive/greenbrain-v2/
```

**Expected result:**
```bash
ls /opt/greenbrain-platform/docs/archive/greenbrain-v2/ | wc -l
# Expected: same count as ls /opt/greenbrain-v2/docs/ | wc -l

ls /opt/greenbrain-v2/docs/ | wc -l
# Compare: both must match
```

**If cp fails with "No such file or directory":** Verify the source: `ls /opt/greenbrain-v2/docs/`.

---

### Step 12 — Copy backend .env.example to apps/backend/

**Purpose:** The reference env template exists in `greenbrain-v2/backend/` but not in the monorepo copy. Copy it so `apps/backend/` is self-contained.

```bash
cp /opt/greenbrain-v2/backend/.env.example \
   /opt/greenbrain-platform/apps/backend/.env.example
```

**Expected result:**
```bash
ls /opt/greenbrain-platform/apps/backend/.env.example
# Expected: file exists

diff /opt/greenbrain-v2/backend/.env.example \
     /opt/greenbrain-platform/apps/backend/.env.example
# Expected: no output (identical)
```

---

## Validation

Run all four checks. All must pass before Wave 1 is declared complete.

```bash
source /opt/greenbrain-platform/infra/scripts/load_env.sh

# --- SQL ---
echo "=== SQL files ===" && ls /opt/greenbrain-platform/sql/schema/
wc -l /opt/greenbrain-platform/sql/schema/supabase-schema.sql
# supabase-schema.sql must exist and be > 1000 lines

ls /opt/greenbrain-platform/sql/migrations/ | wc -l
# Must be: 8

grep "cron.schedule" /opt/greenbrain-platform/sql/cron/pg_cron_canonical.sql | wc -l
# Must be: 10

# --- .bak files gone ---
echo "=== Stale .bak files ==="
find /etc/systemd/system -name "gh-*.bak*" | wc -l
# Must be: 0

find /opt/greenbrain-platform/apps/backend -name "*.bak*" | wc -l
# Must be: 0

find /opt/greenbrain-platform/infra/systemd -name "*.bak*" | wc -l
# Must be: 0

# --- systemd/ flattened ---
echo "=== systemd structure ==="
ls /opt/greenbrain-platform/infra/systemd/*.service \
   /opt/greenbrain-platform/infra/systemd/*.timer | wc -l
# Must be: 12

test -d /opt/greenbrain-platform/infra/systemd/current && echo "FAIL: current/ still exists" || echo "OK: current/ removed"
test -d /opt/greenbrain-platform/infra/systemd/next && echo "FAIL: next/ still exists" || echo "OK: next/ removed"

test -x /opt/greenbrain-platform/infra/systemd/install.sh && echo "OK: install.sh executable" || echo "FAIL"

# --- docs and backend ---
ls /opt/greenbrain-platform/docs/archive/greenbrain-v2/ | wc -l
# Must be > 0

ls /opt/greenbrain-platform/apps/backend/.env.example
# Must exist

# --- Wave 4 artifacts still intact ---
find /opt/greenbrain-platform/apps/ml-worker -name "*.bak_phase*" | wc -l
# Must still be: 7

# --- Live services still healthy ---
echo "=== Runtime health ==="
systemctl list-timers --all | grep gh- | wc -l
# Must be: 6

docker ps --format "{{.Names}}: {{.Status}}" | grep gb_v2 | wc -l
# Must be: 6
```

---

## Rollback

All Wave 1 actions are non-destructive to runtime. Rollback is trivial:

| Action | Rollback |
|--------|---------|
| Supabase schema export | `rm sql/schema/supabase-schema.sql` |
| sql/migrations/ populated | `rm sql/migrations/*.sql` |
| sql/cron/ written | `rm sql/cron/pg_cron_canonical.sql` |
| .gitignore entries added | Remove the appended block (marked with `# Wave 1` comment) |
| `/etc/systemd/system/*.bak*` deleted | Not worth restoring — these are confirmed non-loaded files |
| `apps/backend/*.bak` deleted | Restore from `git checkout apps/backend/app/core/config.py.bak` if needed |
| `infra/systemd/` flattened | Unit files are still in `/etc/systemd/system/` — copy back if needed |
| `docs/archive/greenbrain-v2/` created | `rm -rf docs/archive/` |
| `apps/backend/.env.example` copied | `rm apps/backend/.env.example` |

No systemd reload was performed. No Docker restart was performed. Rolling back any of these has zero production impact.

---

## Output artifacts

All must exist after Wave 1 is complete:

| Artifact | Path | Verify |
|----------|------|--------|
| Supabase schema snapshot | `sql/schema/supabase-schema.sql` | `wc -l` > 1000 |
| Migration files | `sql/migrations/001–008_blocco_*.sql` | `ls \| wc -l` = 8 |
| pg_cron canonical SQL | `sql/cron/pg_cron_canonical.sql` | 10 `cron.schedule` calls |
| SQL README | `sql/README.md` | exists |
| Updated .gitignore | `.gitignore` | contains `parquet_cache/` |
| Clean systemd dir | `infra/systemd/*.service` + `*.timer` | 12 files, no subdirs |
| Systemd install script | `infra/systemd/install.sh` | executable |
| Archived old docs | `docs/archive/greenbrain-v2/` | non-empty |
| Backend env template | `apps/backend/.env.example` | exists |
| Wave 4 artifacts intact | `apps/ml-worker/*.bak_phase*` | count = 7 |

---

## Wave 1 status at runbook creation

| Step | Status | Notes |
|------|--------|-------|
| `sql/schema/` directory | ✅ Exists | `current-schema.sql` already present (local Docker dump) |
| `sql/schema/supabase-schema.sql` | ⬜ Pending | Step 1 |
| `sql/migrations/` directory | ✅ Exists (empty) | Step 2 |
| `sql/migrations/` populated | ⬜ Pending | Step 2 |
| `sql/cron/` directory | ✅ Exists (empty) | Step 3 |
| `sql/cron/pg_cron_canonical.sql` | ⬜ Pending | Step 3 |
| `sql/README.md` | ⬜ Pending | Step 4 |
| `.gitignore` updated | ⬜ Pending | Step 5 |
| `/etc/systemd/system/*.bak*` (9 files) | ⬜ Pending | Step 6 |
| `apps/backend/*.bak` (2 files) | ⬜ Pending | Step 7 |
| `infra/systemd/current/*.bak*` (4 files) | ⬜ Pending | Step 8 |
| `infra/systemd/` flattened | ⬜ Pending | Steps 8–9 (use `next/` as source) |
| `infra/systemd/install.sh` | ⬜ Pending | Step 10 |
| `docs/archive/greenbrain-v2/` | ⬜ Pending | Step 11 |
| `apps/backend/.env.example` | ⬜ Pending | Step 12 |
