# Dev-Cloud Execution Plan
> Step-by-step plan to make `greenbrain-platform` the single real source of truth
> for the dev-cloud execution mode.
> Updated: 2026-04-02.
> Evidence: `docs/architecture/greenbrain-canonical-architecture.md` ·
> `docs/migration/source-of-truth.md` · `docs/architecture/master-roadmap-to-product.md`

---

## Execution notation

Each step is tagged:
- `[TERMINAL]` — run in shell; no code editing
- `[CASCADE]` — file edits suited to Cascade-assisted refactor
- `[MANUAL]` — requires human decision or external action (key rotation, etc.)

---

## !! Do NOT Touch These Yet !!

Until the section that explicitly unlocks them:

| Path / object | Reason | Unlocked in |
|---|---|---|
| `/opt/greenhouse/repo/*.py` | Live source for 5/6 ML jobs; changes here have zero effect after migration | §5 (confirmed daily cycle) |
| `WorkingDirectory` in `gh-train-biweekly/quarterly` | Changing while shell scripts still `cd` to legacy causes import failure | §5 (shell scripts fixed first) |
| `EnvironmentFile=/opt/greenhouse/.env` removal | 2 services depend on it entirely | §5 (all vars confirmed in `dev.env`) |
| `docker-compose` frontend volume | Changing before `apps/frontend/.env` exists breaks container | §7 (`.env` copied first) |
| `@supabase/supabase-js` in `package.json` | Removing before FastAPI JWT is live = immediate login failure for all users | §8 (JWT live and tested) |
| Supabase PostgreSQL live schema (DDL) | No migration runner, no rollback | §2 (`sql/migrate.sh` first) |
| pg_cron jobs #11–13, #28–29, #31–37 | Active ETL and planner schedule; disabling any breaks data pipeline | Never without tested replacement |

---

## Analytics Regression Invariant

**After every section**, before marking it done, verify these 5 endpoints remain
non-empty in the running dev-cloud stack:

```bash
curl -s "http://localhost:8002/api/v1/analytics/series-breakdown?entity_type=famiglia&granularity=day" | jq '.data | length'
curl -s "http://localhost:8002/api/v1/analytics/future-windows-stats?entity_type=famiglia" | jq '.data | length'
curl -s "http://localhost:8002/api/v1/analytics/compare-series?entity_type=famiglia&granularity=day" | jq '.data | length'
curl -s "http://localhost:8002/api/v1/dashboard/reorder-suggestions" | jq '.data | length'
curl -s "http://localhost:8002/api/v1/analytics/entity-summary?entity_type=famiglia" | jq '.tree | length'
```

All five must return a count > 0. If any returns 0 or errors, stop and investigate
before proceeding.

---

## Section 1 — Immediate Low-Risk Fixes

No services are restarted. No code is changed. Zero rollback risk.

---

### Step 1.1 — Disable pg_cron rogue jobs
`[TERMINAL]` `[MANUAL]`

**Objective:** Stop rogue every-minute ETL triggers (#30, #38, #39) on Supabase.

**Files/components:** Supabase cloud PostgreSQL — `cron.job` table

**Dependencies:** None

**Execution:**
```sql
-- Run in Supabase SQL editor or psql against Supabase
SELECT jobid, jobname, schedule FROM cron.job WHERE jobid IN (30, 38, 39);
-- Verify these are the rogue duplicates, then:
SELECT cron.unschedule(30);
SELECT cron.unschedule(38);
SELECT cron.unschedule(39);
-- Confirm only 10 jobs remain:
SELECT jobid, jobname, schedule FROM cron.job ORDER BY jobid;
```

**Validation:** ETL still runs at correct times (check `cron.job_run_details` after next
scheduled run). Supabase Postgres CPU load reduces.

**Rollback:** `SELECT cron.schedule(...)` to re-add if ETL breaks. Full SQL is in
`sql/cron/pg_cron_canonical.sql` (Step 2.3).

---

### Step 1.2 — Delete credential files and rotate secrets
`[TERMINAL]` `[MANUAL]`

**Objective:** Remove credentials from the source tree; rotate exposed secrets.

**Files/components touched:**
- `lovabel .env corretto.json` (×2 — monorepo root + any other location)
- `docs/operations/env-live.txt`
- Supabase `SUPABASE_SERVICE_ROLE_KEY` (rotate in Supabase dashboard)
- DO Spaces `DO_SPACES_SECRET` (rotate in DigitalOcean console)

**Dependencies:** None

**Execution:**
```bash
# Find all copies
grep -r "SUPABASE_SERVICE_ROLE" /opt/greenbrain-platform --include="*.json" --include="*.txt" -l
find /opt/greenbrain-platform -name "*.env*" -not -path "*/.git/*" | xargs grep -l "service_role" 2>/dev/null

# Delete
rm "/opt/greenbrain-platform/lovabel .env corretto.json"
rm /opt/greenbrain-platform/docs/operations/env-live.txt

# Add to .gitignore
echo "*.env.corretto*" >> /opt/greenbrain-platform/.gitignore
echo "env-live.txt"    >> /opt/greenbrain-platform/.gitignore
```

After deleting: rotate both secrets externally. Update `infra/env/dev.env` and
`/opt/greenhouse/.env` with new values before any ML job next runs.

**Validation:** `git status` — no credential files tracked.
`grep -r "service_role_key" /opt/greenbrain-platform --include="*.json"` — no output.

**Rollback:** N/A — deletion is intentional. New secret values go into `infra/env/dev.env` only.

---

### Step 1.3 — Delete stale .bak* files
`[TERMINAL]`

**Objective:** Remove leftover backup files from previous failed/partial migrations.

**Files/components touched:**
- `/etc/systemd/system/gh-*.bak*` (9 files)
- `apps/backend/app/core/config.py.bak`
- `apps/backend/app/api/v1/ops.py.bak`
- `infra/env/dev.env.bak_wave2`, `dev.env.bak_wave3`

**Dependencies:** Step 1.2 (clean sweep; do together)

**Execution:**
```bash
# Confirm before deleting
ls /etc/systemd/system/gh-*.bak* 2>/dev/null
ls /opt/greenbrain-platform/apps/backend/app/core/config.py.bak 2>/dev/null
ls /opt/greenbrain-platform/infra/env/dev.env.bak_* 2>/dev/null

sudo rm /etc/systemd/system/gh-*.bak*
rm /opt/greenbrain-platform/apps/backend/app/core/config.py.bak
rm /opt/greenbrain-platform/apps/backend/app/api/v1/ops.py.bak
rm /opt/greenbrain-platform/infra/env/dev.env.bak_wave2
rm /opt/greenbrain-platform/infra/env/dev.env.bak_wave3
```

**Validation:** `ls /etc/systemd/system/gh-*.bak*` — no output.

**Rollback:** N/A — these are stale backups. Active units are unchanged.

---

### Step 1.4 — Add SUPABASE_DB_* aliases to dev.env
`[CASCADE]`

**Objective:** Allow ML scripts that reference `SUPABASE_DB_*` vars to resolve them
from `infra/env/dev.env` instead of requiring a separate env file.

**Files/components touched:** `infra/env/dev.env`

**Dependencies:** Step 1.2 (new rotated values must be in place first)

**Execution:** Append to `infra/env/dev.env`:
```bash
# Aliases required by export_features_dense.py and related ML scripts
SUPABASE_DB_HOST=${PG_HOST}
SUPABASE_DB_PORT=${PG_PORT}
SUPABASE_DB_NAME=${PG_DATABASE}
SUPABASE_DB_USER=${PG_USER}
SUPABASE_DB_PASSWORD=${PG_PASSWORD}
```

**Validation:**
```bash
source /opt/greenbrain-platform/infra/env/dev.env
echo $SUPABASE_DB_HOST  # should print PG_HOST value
```

**Rollback:** Remove the 5 appended lines from `dev.env`.

---

### Step 1.5 — Update .gitignore
`[CASCADE]`

**Objective:** Ensure generated artifacts and credential patterns are never tracked.

**Files/components touched:** `/opt/greenbrain-platform/.gitignore`

**Dependencies:** Step 1.2

**Add these entries if not already present:**
```
parquet_cache/
models_v4/
priors_cache/
__pycache__/
*.bak
*.bak_*
.env
env-live.txt
*.env.corretto*
```

**Validation:** `git status` — none of the above appear as untracked.

**Rollback:** N/A — additive change.

---

## Section 2 — SQL Canonicalization

Establishes `sql/` as the versioned home for schema, migrations, and pg_cron jobs.
No DDL is applied to Supabase in this section. Read-only extraction and file creation only.

---

### Step 2.1 — Move historical migration files to sql/migrations/
`[TERMINAL]` `[CASCADE]`

**Objective:** Bring 8 historical migration files under the canonical location.

**Files/components touched:**
- `apps/backend/app/api/v1/jobs/migrations/blocco_*_migration.sql` (8 files)
- `sql/migrations/` (create if absent)

**Dependencies:** Step 1.3 (bak files deleted; clean state)

**Execution:**
```bash
mkdir -p /opt/greenbrain-platform/sql/migrations
ls /opt/greenbrain-platform/apps/backend/app/api/v1/jobs/migrations/

# Rename with ordered prefix as you move
cp .../blocco_ordini_migration.sql sql/migrations/001_blocco_ordini.sql
# ... repeat for all 8
```

Keep the originals in place for now; do not delete until `sql/migrate.sh` is validated.

**Validation:** `ls sql/migrations/` shows 8 files in numbered order.

**Rollback:** Delete `sql/migrations/`; originals untouched.

---

### Step 2.2 — Write sql/migrate.sh
`[CASCADE]`

**Objective:** Provide an idempotent migration runner for applying `sql/migrations/`
files in order.

**Files/components touched:** `sql/migrate.sh` (new file)

**Dependencies:** Step 2.1

**Content pattern:**
```bash
#!/usr/bin/env bash
set -euo pipefail
MIGRATIONS_DIR="$(dirname "$0")/migrations"
for f in "$MIGRATIONS_DIR"/*.sql; do
    echo "Applying $f..."
    psql "$DATABASE_URL" -f "$f"
done
echo "All migrations applied."
```

**Validation:** `bash sql/migrate.sh` against a test DB — no errors; idempotent on
second run.

**Rollback:** Script is additive; reverting a specific migration requires manual SQL.

---

### Step 2.3 — Write sql/cron/pg_cron_canonical.sql
`[CASCADE]`

**Objective:** Version-control the 10 correct pg_cron jobs so any reinstall is
reproducible.

**Files/components touched:** `sql/cron/pg_cron_canonical.sql` (new file)

**Dependencies:** Step 1.1 (rogue jobs disabled; 10 correct jobs remain)

**Execution:** Query Supabase for current canonical jobs:
```sql
SELECT jobid, jobname, schedule, command FROM cron.job ORDER BY jobid;
```
Transcribe all 10 into `sql/cron/pg_cron_canonical.sql` as `SELECT cron.schedule(...)` calls.

**Validation:** File exists; job count in file matches count in Supabase (10).

**Rollback:** N/A — this file is documentation only; it does not modify Supabase.

---

### Step 2.4 — Export Supabase schema snapshot
`[TERMINAL]`

**Objective:** Capture the current live Supabase DDL in version control so drift
can be tracked.

**Files/components touched:** `sql/schema/supabase-snapshot.sql` (new file)

**Dependencies:** None (read-only operation)

**Execution:**
```bash
mkdir -p /opt/greenbrain-platform/sql/schema
pg_dump "$SUPABASE_DATABASE_URL" --schema-only   --no-owner --no-acl   -n public -n analytics -n ml_ops -n ml_forecast   -f /opt/greenbrain-platform/sql/schema/supabase-snapshot.sql
```

**Validation:** File is non-empty; spot-check for `t_core_analytics__series_*` and
`greenhouse_forecast_results_v2` table definitions.

**Rollback:** N/A — read-only.

---

### Step 2.5 — Document schema drift
`[CASCADE]`

**Objective:** Record the known differences between `supabase-snapshot.sql` and
`greenbrain-v2/database/current-schema.sql` so that the local Docker DB can be
brought in sync deliberately.

**Files/components touched:** `sql/schema/drift-notes.md` (new file)

**Dependencies:** Step 2.4

**Method:** `diff sql/schema/supabase-snapshot.sql greenbrain-v2/database/current-schema.sql`
Document each divergence. Do not apply any DDL to Supabase or local Docker in this step.

**Validation:** File exists with at least a summary of differences found.

**Rollback:** N/A — documentation only.

---

## Section 3 — Scheduler Cleanup

Cleans up systemd unit file duplication. No services are restarted.

---

### Step 3.1 — Flatten infra/systemd/current/ into infra/systemd/
`[TERMINAL]`

**Objective:** Eliminate the `current/` subdirectory; `infra/systemd/` is the flat SoT.

**Files/components touched:** `infra/systemd/current/` → `infra/systemd/`

**Dependencies:** Step 1.3 (bak files deleted)

**Execution:**
```bash
ls /opt/greenbrain-platform/infra/systemd/current/
cp /opt/greenbrain-platform/infra/systemd/current/*.{service,timer}    /opt/greenbrain-platform/infra/systemd/
rmdir /opt/greenbrain-platform/infra/systemd/current
```

Only do this if `current/` contains files not already present in `infra/systemd/`.
If duplicates: compare diffs first; keep the monorepo version.

**Validation:** `ls infra/systemd/` shows all 12 unit files flat; no `current/` subdir.

**Rollback:** `mkdir infra/systemd/current && mv ... current/` — deployed units at
`/etc/systemd/system/` are untouched.

---

### Step 3.2 — Write infra/systemd/install.sh
`[CASCADE]`

**Objective:** Provide a reproducible way to (re)deploy all systemd units from the
monorepo.

**Files/components touched:** `infra/systemd/install.sh` (new file)

**Dependencies:** Step 3.1

**Content pattern:**
```bash
#!/usr/bin/env bash
set -euo pipefail
SYSTEMD_DIR="$(dirname "$0")"
sudo cp "$SYSTEMD_DIR"/*.service /etc/systemd/system/
sudo cp "$SYSTEMD_DIR"/*.timer   /etc/systemd/system/
sudo systemctl daemon-reload
echo "Systemd units installed."
```

**Validation:** `bash infra/systemd/install.sh --dry-run` (add dry-run flag) — no errors.

**Rollback:** N/A — existing deployed units unchanged until the script is actually run.

---

## Section 4 — Storage Abstraction Wiring

Wires `apps/ml-worker/storage/` factory into the 4 ML files that still use direct
SDK calls. Applied one file at a time with smoke testing between each.

**Context:** `.bak_phase2b_fix`, `.bak_phase2b`, `.bak_phase2c` files already contain
the correct new versions. This section applies them.

---

### Step 4.1 — Wire data_access_v1.py (first file)
`[CASCADE]`

**Objective:** Replace direct Supabase storage SDK calls in `data_access_v1.py` with
`StorageBackend` factory. This is the highest-risk file — validate before proceeding.

**Files/components touched:**
- `apps/ml-worker/data_access_v1.py`
- Reference: `apps/ml-worker/data_access_v1.py.bak_phase2b_fix`

**Dependencies:** Step 1.4 (SUPABASE_DB_* aliases in dev.env)

**Execution:** Apply the diff from `.bak_phase2b_fix`. The change replaces
`create_client(SUPABASE_URL, SUPABASE_KEY)` calls with `get_storage_backend()` factory.

**Validation — smoke test (do not skip):**
```bash
cd /opt/greenbrain-platform/apps/ml-worker
STORAGE_BACKEND=supabase PREDICT_LIMIT=1 python -c "from data_access_v1 import load_parquet_for_family; print('import ok')"
```
Then run a single-family predict dry run:
```bash
STORAGE_BACKEND=supabase PREDICT_LIMIT=1 python jobs/run_predict_family.py --family TEST_FAMILY
```
Verify output is identical to a run from `/opt/greenhouse/repo/`.

**Rollback:**
```bash
cp apps/ml-worker/data_access_v1.py.bak_phase2b_fix.orig apps/ml-worker/data_access_v1.py
```
(Keep original as `.orig` before applying the patch.)

---

### Step 4.2 — Wire export_features_dense.py
`[CASCADE]`

**Objective:** Replace Supabase SDK calls in `export_features_dense.py` with
`StorageBackend`.

**Files/components touched:**
- `apps/ml-worker/export_features_dense.py`
- Reference: `apps/ml-worker/export_features_dense.py.bak_phase2b`

**Dependencies:** Step 4.1 (same pattern; must pass first)

**Validation:**
```bash
STORAGE_BACKEND=supabase python -c "from export_features_dense import main; print('import ok')"
```
Then: `STORAGE_BACKEND=supabase EXPORT_LIMIT=1 python export_features_dense.py`

**Rollback:** Restore from `.orig` backup taken before applying patch.

---

### Step 4.3 — Wire priors upload/download scripts
`[CASCADE]`

**Objective:** Replace Supabase SDK calls in both priors scripts with `StorageBackend`.

**Files/components touched:**
- `apps/ml-worker/jobs/upload_priors_to_supabase.py`
- `apps/ml-worker/jobs/download_priors_from_supabase.py`
- Reference: `.bak_phase2c` variants

**Dependencies:** Step 4.2

**Validation:**
```bash
STORAGE_BACKEND=supabase python -c   "from jobs.upload_priors_to_supabase import main; print('import ok')"
```

**Rollback:** Restore from `.orig` backups.

---

### Step 4.4 — Delete .bak_phase2* files
`[TERMINAL]`

**Objective:** Remove the migration reference files now that all 4 files are patched
and smoke-tested.

**Files/components touched:** All `*.bak_phase2*` files in `apps/ml-worker/`

**Dependencies:** Steps 4.1–4.3 all validated

**Execution:**
```bash
find /opt/greenbrain-platform/apps/ml-worker -name "*.bak_phase2*" | xargs rm
```

**Validation:** `find apps/ml-worker -name "*.bak*"` — no output.

**Rollback:** N/A — patches already applied and validated.

---

## Section 5 — ML Monorepo Consolidation

Makes `apps/ml-worker/` the live execution path for all 6 ML systemd jobs.
This is the highest-risk section. Validate each step before the next.

---

### Step 5.1 — Fix GH_REPO_DIR in infra/env/dev.env
`[CASCADE]`

**Objective:** Point `GH_REPO_DIR` to the monorepo ML worker path so shell scripts
use the correct working directory.

**Files/components touched:** `infra/env/dev.env`

**Dependencies:** Section 4 complete

**Change:**
```bash
# Before:
GH_REPO_DIR=/opt/greenhouse/repo

# After:
GH_REPO_DIR=/opt/greenbrain-platform/apps/ml-worker
```

**Validation:** `source infra/env/dev.env && echo $GH_REPO_DIR` — prints monorepo path.

**Rollback:** Revert the one line in `dev.env`.

---

### Step 5.2 — Fix ML shell scripts to use GH_REPO_DIR
`[CASCADE]`

**Objective:** Remove hardcoded `cd /opt/greenhouse/repo` from all 3 ML shell scripts.

**Files/components touched:**
- `infra/scripts/run_predict_all.sh`
- `infra/scripts/run_train_missing.sh`
- `infra/scripts/run_daily_parquet_batches.sh`

**Dependencies:** Step 5.1

**Change pattern:** Replace `cd /opt/greenhouse/repo` with `cd "$GH_REPO_DIR"` in
each script. Ensure `source .../load_env.sh` runs before the `cd`.

**Validation:** Dry-run each script with `GH_REPO_DIR` set:
```bash
GH_REPO_DIR=/opt/greenbrain-platform/apps/ml-worker   bash -n infra/scripts/run_predict_all.sh  # syntax check
```

**Rollback:** Revert the `cd` line in each script.

---

### Step 5.3 — Migrate gh-train-biweekly-all to load_env.sh
`[CASCADE]` `[TERMINAL]`

**Objective:** Replace `EnvironmentFile=/opt/greenhouse/.env` with the `load_env.sh`
mechanism in `gh-train-biweekly-all.service`.

**Files/components touched:**
- `infra/systemd/gh-train-biweekly-all.service`
- `/etc/systemd/system/gh-train-biweekly-all.service`

**Dependencies:** Step 5.1 (all vars confirmed in `dev.env`); Step 5.2

**Change:**
```ini
# Remove:
EnvironmentFile=/opt/greenhouse/.env

# Replace ExecStart to source load_env.sh first:
ExecStart=/bin/bash -c 'source /opt/greenbrain-platform/infra/env/load_env.sh &&   bash /opt/greenbrain-platform/infra/scripts/run_train_biweekly.sh'
```

**Deployment:**
```bash
sudo cp infra/systemd/gh-train-biweekly-all.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl status gh-train-biweekly-all.service
```

**Validation:** Next scheduled run succeeds (`journalctl -u gh-train-biweekly-all -n 50`).
For immediate test: `sudo systemctl start gh-train-biweekly-all` with `TRAIN_LIMIT=1`.

**Rollback:**
```bash
sudo cp /etc/systemd/system/gh-train-biweekly-all.service.orig /etc/systemd/system/
sudo systemctl daemon-reload
```

---

### Step 5.4 — Migrate gh-train-quarterly to load_env.sh
`[CASCADE]` `[TERMINAL]`

**Objective:** Same as Step 5.3 for `gh-train-quarterly.service`.

**Files/components touched:**
- `infra/systemd/gh-train-quarterly.service`
- `/etc/systemd/system/gh-train-quarterly.service`

**Dependencies:** Step 5.3 validated

Same pattern as 5.3. After deployment, verify `journalctl -u gh-train-quarterly -n 20`
shows it reads env from `load_env.sh`.

---

### Step 5.5 — Validate full daily ML cycle from monorepo
`[TERMINAL]`

**Objective:** Confirm that `gh-predict-all` and `gh-train-missing` run correctly
from `apps/ml-worker/` with correct storage behavior.

**Dependencies:** Steps 5.2–5.4

**Execution:**
```bash
# Manually trigger predict with LIMIT
sudo systemctl start gh-predict-all
journalctl -u gh-predict-all -f
```

Watch for:
- `Working directory: /opt/greenbrain-platform/apps/ml-worker`
- No `ModuleNotFoundError`
- `STORAGE_BACKEND=supabase` in log (or env)
- Rows written to `greenhouse_forecast_results_v2`

**Validation:** Row count in `greenhouse_forecast_results_v2` increases after run.
Analytics regression check (see top of document).

**Rollback:** If `gh-predict-all` fails, revert shell script `cd` change (Step 5.2);
`daemon-reload`; confirm it runs from legacy path again.

---

### Step 5.6 — Archive /opt/greenhouse/repo/
`[TERMINAL]`

**Objective:** Make the legacy ML repo read-only so accidental edits there are
impossible.

**Dependencies:** Step 5.5 validated (one full daily cycle from monorepo confirmed)

**Execution:**
```bash
# Mark as archived, do not delete (kept for emergency rollback)
sudo touch /opt/greenhouse/repo/ARCHIVED
sudo chmod -R a-w /opt/greenhouse/repo
```

**Validation:** `ls -la /opt/greenhouse/repo/ARCHIVED` — exists.
`echo test > /opt/greenhouse/repo/test.txt` — permission denied.

**Rollback:** `sudo chmod -R u+w /opt/greenhouse/repo` restores write access.

---

## Section 6 — Backend Dockerization

Moves the running `gb_v2_backend` Docker container to mount `apps/backend/` instead
of the legacy path.

---

### Step 6.1 — Write apps/backend/Dockerfile
`[CASCADE]`

**Objective:** Create a production uvicorn Dockerfile for the FastAPI backend.

**Files/components touched:** `apps/backend/Dockerfile` (new file)

**Dependencies:** Section 4 (storage abstraction; clean backend)

**Content:**
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8002"]
```

**Validation:**
```bash
docker build -t gb_v2_backend_test apps/backend/
docker run --rm gb_v2_backend_test python -c "from app.main import app; print('ok')"
```

**Rollback:** Delete the Dockerfile; container still runs from volume mount.

---

### Step 6.2 — Update docker-compose backend volume
`[CASCADE]`

**Objective:** Point the backend container's source volume at `apps/backend/` instead
of the legacy path.

**Files/components touched:** `infra/docker/docker-compose.base.yml` (and/or the
active compose file in `/opt/greenbrain-v2/deploy/`)

**Dependencies:** Step 6.1 (Dockerfile confirmed buildable); `apps/backend/` confirmed
in sync with legacy path

**Change:**
```yaml
# Before:
volumes:
  - /opt/greenbrain-v2/backend:/app

# After:
volumes:
  - /opt/greenbrain-platform/apps/backend:/app
```

**Deployment:**
```bash
docker-compose -f /opt/greenbrain-v2/deploy/docker-compose.base.yml   -f /opt/greenbrain-v2/deploy/docker-compose.dev.yml up -d --no-build backend
```

**Validation:**
```bash
docker exec gb_v2_backend curl -s http://localhost:8002/health | jq .
docker inspect gb_v2_backend | grep -A2 Mounts | grep Source
```
Source must show `apps/backend`. Analytics regression check.

**Rollback:** Revert volume path; `docker-compose up -d backend`.

---

## Section 7 — Frontend Dockerization

Produces a production nginx + Vite build image for the frontend. Auth replacement
(Section 8) is **not** required before dockerization — the Supabase-auth build still
works; the Dockerfile change is infrastructure only.

---

### Step 7.1 — Copy .env and supabase/ config into apps/frontend/
`[TERMINAL]`

**Objective:** Ensure `apps/frontend/` has the `.env` and Supabase config it needs
to build from the monorepo path.

**Files/components touched:**
- `apps/frontend/.env` (create from legacy path copy)
- `apps/frontend/src/integrations/supabase/` (confirm it exists in monorepo)

**Dependencies:** Section 6 (backend confirmed from monorepo; dev.env clean)

**Execution:**
```bash
# Copy .env from legacy frontend location
cp /opt/greenbrain/frontend/.env /opt/greenbrain-platform/apps/frontend/.env
# Add to .gitignore if not already
grep -q "^apps/frontend/.env" .gitignore || echo "apps/frontend/.env" >> .gitignore
```

**Validation:** `cat apps/frontend/.env` — shows `VITE_API_BASE_URL` and Supabase vars.

**Rollback:** Delete the copied `.env`.

---

### Step 7.2 — Resolve lock file conflict
`[TERMINAL]`

**Objective:** Choose one package manager; remove the other lock file.

**Files/components touched:** `apps/frontend/package-lock.json` or `apps/frontend/bun.lock`

**Dependencies:** Step 7.1

**Decision:**
```bash
# Check which is fresher and which CI/Docker will use
ls -la apps/frontend/package-lock.json apps/frontend/bun.lock

# If keeping npm:
rm apps/frontend/bun.lock
npm install --prefix apps/frontend  # regenerate package-lock

# If keeping bun:
rm apps/frontend/package-lock.json
```

**Validation:** `npm run build --prefix apps/frontend` completes without errors.

**Rollback:** `git checkout apps/frontend/package-lock.json` restores the removed file.

---

### Step 7.3 — Write apps/frontend/Dockerfile
`[CASCADE]`

**Objective:** Create a production Vite build + nginx image.

**Files/components touched:** `apps/frontend/Dockerfile` (new file)

**Dependencies:** Step 7.2

**Content:**
```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```

`nginx.conf` must include `try_files $uri $uri/ /index.html;` for React Router.

**Validation:**
```bash
docker build -t gb_v2_frontend_test apps/frontend/
docker run -d -p 8090:80 --name fe_test gb_v2_frontend_test
curl -s http://localhost:8090/  # should return HTML
docker rm -f fe_test
```

**Rollback:** Delete the Dockerfile; container continues as Vite dev server.

---

### Step 7.4 — Switch docker-compose frontend to production image
`[CASCADE]` `[TERMINAL]`

**Objective:** Replace the Vite dev server container with the production nginx build.

**Files/components touched:**
- `infra/docker/docker-compose.base.yml` frontend service definition
- Active compose file in `/opt/greenbrain-v2/deploy/`

**Dependencies:** Step 7.3 (image builds and serves correctly)

**Change:**
```yaml
frontend:
  build:
    context: /opt/greenbrain-platform/apps/frontend
    dockerfile: Dockerfile
  # Remove: volumes + command for dev server
  ports:
    - "8083:80"
  restart: unless-stopped
```

**Deployment:**
```bash
docker-compose up -d --build frontend
curl -s http://localhost:8083/ | head -5
```

**Validation:** Frontend loads in browser. Login still works (Supabase auth still
present at this stage). Analytics regression check.

**Rollback:** Revert compose change; `docker-compose up -d frontend` restores dev server.

---

### Step 7.5 — Remove dead gb_v2_ml container
`[CASCADE]`

**Objective:** Remove the `sleep infinity` placeholder container from compose.

**Files/components touched:** `infra/docker/docker-compose.base.yml`

**Dependencies:** Step 7.4

**Change:** Delete the `ml:` service block from the compose file.

**Validation:** `docker-compose config` — no `gb_v2_ml` service; `docker ps` — no
`gb_v2_ml` after next `docker-compose up`.

**Rollback:** Re-add the stub service block.

---

## Section 8 — Auth Replacement

Replaces Supabase JS auth with FastAPI JWT. This is the most impactful frontend
change. Must not start until all previous sections are stable.

---

### Step 8.1 — Implement FastAPI auth endpoints
`[CASCADE]`

**Objective:** Create `POST /api/v1/auth/login` and `GET /api/v1/auth/me` in the
FastAPI backend.

**Files/components touched:**
- `apps/backend/app/api/v1/auth.py` (new file)
- `apps/backend/app/api/v1/__init__.py` or router registration
- `apps/backend/app/core/security.py` (JWT utility — new or extend existing)

**Dependencies:** Section 6 complete (backend from monorepo; production image working)

**Implementation:**
- `POST /api/v1/auth/login` — accepts `{email, password}`, validates against
  `users` table (or equivalent), returns `{access_token, token_type}`
- `GET /api/v1/auth/me` — validates JWT from `Authorization: Bearer <token>`,
  returns user profile
- Use `python-jose` or `PyJWT` for JWT; `passlib` for password hashing

**Validation:**
```bash
curl -X POST http://localhost:8002/api/v1/auth/login   -H "Content-Type: application/json"   -d '{"email":"test@test.com","password":"testpass"}' | jq .access_token
```

**Rollback:** Comment out auth router registration; Supabase auth still in frontend.

---

### Step 8.2 — Implement GET /api/v1/settings/garden-center
`[CASCADE]`

**Objective:** Replace the direct Supabase PostgREST call in `useGardenCenterSettings.ts`
with a FastAPI endpoint.

**Files/components touched:**
- `apps/backend/app/api/v1/settings.py` (new or extend existing)

**Dependencies:** Step 8.1

**Validation:**
```bash
curl -s http://localhost:8002/api/v1/settings/garden-center   -H "Authorization: Bearer <token>" | jq .
```

**Rollback:** Endpoint can stay live without the frontend using it yet.

---

### Step 8.3 — Replace frontend auth hooks
`[CASCADE]`

**Objective:** Replace Supabase JS auth in the React app with FastAPI JWT calls.

**Files/components touched:**
- `apps/frontend/src/hooks/useAuth.tsx` — replace with FastAPI JWT implementation
- `apps/frontend/src/hooks/useGardenCenterSettings.ts` — replace with `apiClient.ts` call
- `apps/frontend/src/pages/Login.tsx` — update to call `POST /api/v1/auth/login`
- `apps/frontend/src/components/layout/TopBar.tsx` — update logout to clear JWT

**Dependencies:** Steps 8.1–8.2 (endpoints live and tested)

**Validation:** Login flow works end-to-end in browser. All authenticated routes
load correctly. Analytics regression check after login.

**Rollback:** `git checkout` on all 4 files restores Supabase hooks.

---

### Step 8.4 — Remove Supabase JS dependency
`[CASCADE]` `[TERMINAL]`

**Objective:** Remove `@supabase/supabase-js` and the `integrations/supabase/` folder
now that all callers are replaced.

**Files/components touched:**
- `apps/frontend/src/integrations/supabase/client.ts` — delete
- `apps/frontend/src/integrations/supabase/` — delete directory if empty
- `apps/frontend/package.json` — remove `@supabase/supabase-js`

**Dependencies:** Step 8.3 validated; login tested in browser with JWT

**Execution:**
```bash
cd apps/frontend
npm uninstall @supabase/supabase-js
rm -rf src/integrations/supabase
npm run build  # must succeed with no Supabase imports
```

**Validation:**
```bash
grep -r "supabase" apps/frontend/src/  # must return nothing
npm run build  # clean build
docker build -t gb_v2_frontend_clean apps/frontend/
```

**Rollback:** `git checkout package.json src/integrations/`; `npm install`.

---

## Section 9 — Final Wiring and Cleanup

---

### Step 9.1 — Move active compose files to infra/docker/
`[TERMINAL]`

**Objective:** Retire `/opt/greenbrain-v2/deploy/` as the active compose location.

**Files/components touched:**
- `infra/docker/docker-compose.base.yml`
- `infra/docker/docker-compose.dev.yml`
- `/opt/greenbrain-v2/deploy/` → archive marker

**Dependencies:** Sections 6–8 complete (all volume mounts on monorepo; all images correct)

**Execution:**
```bash
# Verify infra/docker/ compose files are in sync with what is currently running
diff infra/docker/docker-compose.base.yml /opt/greenbrain-v2/deploy/docker-compose.base.yml

# If in sync, stop using old path:
docker-compose -f infra/docker/docker-compose.base.yml   -f infra/docker/docker-compose.dev.yml up -d

# Archive old location:
sudo touch /opt/greenbrain-v2/deploy/ARCHIVED
sudo chmod -R a-w /opt/greenbrain-v2/deploy
```

**Validation:** `docker ps` shows all 5 containers healthy. Analytics regression check.
`docker inspect gb_v2_backend | grep Source` — shows monorepo path.

**Rollback:** Revert to `docker-compose` from `/opt/greenbrain-v2/deploy/`.

---

### Step 9.2 — Archive legacy source paths
`[TERMINAL]`

**Objective:** Mark legacy paths as read-only so they cannot diverge from monorepo.

**Dependencies:** Step 9.1 validated; all containers confirmed running from monorepo

**Execution:**
```bash
sudo touch /opt/greenbrain-v2/backend/ARCHIVED && sudo chmod -R a-w /opt/greenbrain-v2/backend
sudo touch /opt/greenbrain/frontend/ARCHIVED && sudo chmod -R a-w /opt/greenbrain/frontend
```

**Validation:** `ls /opt/greenbrain-v2/backend/ARCHIVED` — exists.
`echo x > /opt/greenbrain-v2/backend/test` — permission denied.

**Rollback:** `sudo chmod -R u+w /opt/<path>`.

---

## Dev-Cloud Definition of Done

The dev-cloud execution mode is complete when **all** of the following are true:

### Source of truth
- [ ] All Docker containers mount paths under `/opt/greenbrain-platform/`
- [ ] All 6 systemd ML jobs run from `apps/ml-worker/`; `journalctl` shows monorepo `WorkingDirectory`
- [ ] `grep -r /opt/greenhouse /etc/systemd/system/gh-*.service` — no output
- [ ] `grep -r /opt/greenbrain-v2 /etc/systemd/system/` — no output
- [ ] `/opt/greenhouse/repo/ARCHIVED` exists; directory is read-only
- [ ] `/opt/greenbrain-v2/deploy/ARCHIVED` exists

### Schema and SQL
- [ ] `sql/migrations/` contains 8 ordered migration files
- [ ] `sql/migrate.sh` runs idempotently against a test DB
- [ ] `sql/cron/pg_cron_canonical.sql` contains exactly 10 correct jobs
- [ ] `sql/schema/supabase-snapshot.sql` exists and is non-empty
- [ ] pg_cron on Supabase has exactly 10 jobs (no #30/38/39)

### Configuration
- [ ] Single env system: `load_env.sh` used by all 6 ML services
- [ ] `grep -r /opt/greenhouse/.env /etc/systemd/system/` — no output
- [ ] No credential files in any tracked path: `git ls-files | xargs grep -l "service_role"` — no output
- [ ] `infra/env/dev.env` includes `SUPABASE_DB_*` aliases

### Backend
- [ ] `apps/backend/Dockerfile` exists and builds successfully
- [ ] `docker inspect gb_v2_backend | grep Source` shows `apps/backend`
- [ ] `curl http://localhost:8002/health` → 200

### Frontend
- [ ] `apps/frontend/Dockerfile` exists; `docker build` succeeds
- [ ] `gb_v2_frontend` runs production nginx build (not Vite dev server)
- [ ] `docker inspect gb_v2_frontend` — no `npm run dev` command
- [ ] Single lock file: either `package-lock.json` or `bun.lock`; not both

### Auth
- [ ] `POST /api/v1/auth/login` returns JWT
- [ ] Login flow works in browser without Supabase JS
- [ ] `grep -r "supabase" apps/frontend/src/` — no output (other than deleted integrations dir)
- [ ] `@supabase/supabase-js` absent from `apps/frontend/package.json`

### Analytics (regression invariant — must hold throughout)
- [ ] `/api/v1/analytics/series-breakdown` returns non-empty data ✓
- [ ] `/api/v1/analytics/future-windows-stats` returns non-empty data ✓
- [ ] `/api/v1/analytics/compare-series` returns non-empty data ✓
- [ ] `/api/v1/dashboard/reorder-suggestions` returns non-empty data ✓
- [ ] `/api/v1/analytics/entity-summary` returns non-empty tree ✓

### ML
- [ ] `STORAGE_BACKEND=supabase` predict cycle runs from `apps/ml-worker/` — output matches prior runs
- [ ] `gh-parquet-export` still writes to Supabase Storage after storage abstraction wiring
- [ ] `ml_ops.pipeline_run_log_v1` receives a new row after each predict run

---

*For client-local packaging, see `docs/architecture/master-roadmap-to-product.md` Phases 3–6.*
*For schema wave sequencing, see `docs/migration/wave-7b-runbook.md` and sibling runbooks.*


---

> **Note:** The domain rollout (`app.greenbrain.it`, `greenbrain.it`) and customer
> remote access (`<slug>.greenbrain.it`) are confirmed architectural decisions but are
> **secondary workstreams**. They must not delay or displace the steps in this plan.
> See `docs/architecture/final-platform-priority-and-access-decision.md`.
