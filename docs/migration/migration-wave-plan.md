# Greenbrain Migration Wave Plan
> Action-oriented execution plan. Evidence base: inventory (01/02/03), job-catalog, schedules, data-flow, source-of-truth.
> Generated: 2026-03-27.

---

## Conflicts to resolve

1. **`gh-sync-local-artifacts` path:** biweekly/quarterly ExecStartPost uses `/opt/greenhouse/bin/` version. Monorepo version also exists. Wave 2 resolves.
2. **`check_etl_ready.sh` gate:** job-catalog and data-flow both say it queries `etl.t_etl_runs`. Inventory-01 also mentions `ops_parquet_export_state` — this is a separate table written *by* the export job, not a gate source. No conflict.
3. **`gh-train-biweekly-all` actual frequency:** fires only when 1st/15th is a Sunday (~every 6–8 weeks). Cannot be fully tested in the weekly cycle; Wave 3 uses `TRAIN_LIMIT=1` manual start instead.
4. **`SUPABASE_KEY` alias:** `data_access_v1.py` reads this; `dev.env` does not set it. Must be added in Wave 2 before Wave 3 changes the live Python path.

---

## 1. Executive objective

**Current state:** The stack is split across five `/opt` directories. ML production runs from `/opt/greenhouse/repo/`. Dev work (storage abstraction migration) is in the monorepo but not wired to production. Three pg_cron jobs run the full ETL pipeline every minute. A live Supabase JWT is in the source tree of both repos. The API backend reads a local Docker PostgreSQL instance while all ML output is written to Supabase cloud — these two DBs are not synchronized.

**Target state:** `/opt/greenbrain-platform` is the sole development source. All systemd services execute from the monorepo. One env loading system. One bin path. Storage abstraction active, enabling a future client-installable runtime (`client-runtime/`). Legacy paths archived, not deleted.

**Why wave-based:** The system is live. Multiple critical interdependencies mean that changing layers out of order breaks production. Each wave must leave the system fully operational before the next begins.

**Principle: freeze → align → refactor → package.**

---

## 2. Migration principles

1. Do not break live systemd jobs — every wave ends with all 6 timers passing.
2. Do not change multiple layers simultaneously — one domain per wave step.
3. Do not remove a legacy path before the new path is validated end-to-end.
4. Version before refactor — files are moved to monorepo first, then changed.
5. One operational truth per domain — prove the new source before touching the old.
6. One reversible change at a time — each numbered step is independently revertible.
7. Test the cheapest service first — `PREDICT_LIMIT=1` before full runs.
8. Env changes must be additive before subtractive — add new var alongside old; remove old only after confirming new works.
9. Do not touch Supabase credentials, DO Spaces credentials, or pg_cron jobs 11/12/13 during migration.
10. Parallel safe work (docs, `.gitignore`, SQL files) is always unblocked — run independently.

---

## 3. Current blockers

| # | Blocker | Severity | Why it matters | Resolved in |
|---|---------|---------|----------------|-------------|
| B1 | pg_cron 30/38/39 running `* * * * *` | 🔴 Critical | Up to 3 concurrent full ETL invocations/min | Wave 0 |
| B2 | Credential file `lovabel .env corretto.json` in both repos | 🔴 Critical | Live JWT exposed in source tree | Wave 0 |
| B3 | ML Python split-brain: production runs from `/opt/greenhouse/repo/` | 🔴 Critical | Storage abstraction migration invisible to production | Wave 3 |
| B4 | Shell scripts `cd /opt/greenhouse/repo` despite being in monorepo | 🟠 High | Blocks Wave 3 — path redirect defeats monorepo migration | Wave 3 |
| B5 | Two CLI bin sets in PATH with different behavior | 🔴 Critical | Manual interventions may use wrong env/invocation | Wave 2 |
| B6 | biweekly/quarterly use `EnvironmentFile=/opt/greenhouse/.env` | 🟠 High | Secret rotation must happen in 2 places | Wave 2 |
| B7 | `export_features_dense.py` uses `SUPABASE_DB_*` absent from `dev.env` | 🟠 High | Will crash when run from monorepo env system | Wave 2 (alias) |
| B8 | Storage abstraction built but not wired | 🟠 High | `STORAGE_BACKEND=local` untestable; client-runtime blocked | Wave 4 |
| B9 | `apps/frontend/` missing `.env`/`supabase/`; Docker mounts legacy path | 🔴 Critical | Monorepo frontend changes invisible to production | Wave 5 |
| B10 | Docker mounts `/opt/greenbrain-v2/backend/` not monorepo | 🟡 Medium | Will diverge at next code change | Wave 5 |
| B11 | API reads local Docker DB; ML writes Supabase | 🔴 Critical | Frontend may show stale data — architectural gap | Flagged Wave 6; requires separate decision |
| B12 | SQL schema unversioned; pg_cron not in any file | 🟠 High | Cannot reproduce DB from source control | Wave 1 (snapshot) + Wave 6 |
| B13 | `models_v4/` and `parquet_cache/` in source tree | 🟡 Medium | 18GB+ binary data in-tree | Wave 1 |

---

## 4. Migration waves overview

| Wave | Name | Goal | Safe now? | Depends on | Exit criteria |
|------|------|------|-----------|-----------|---------------|
| 0 | Production stabilization | Remove active dangers; baseline | ✅ Yes | — | Jobs 30/38/39 gone; credential deleted; all timers active |
| 1 | Repo canonicalization | SQL structure, cleanup, .gitignore | ✅ Yes (parallel w/ 0) | — | sql/ populated; no .bak in wrong places; .gitignore correct |
| 2 | Env/config + CLI | One env system; one bin path | ✅ After Wave 0 | Wave 0 | All 6 services use `load_env.sh`; biweekly/quarterly TRAIN_LIMIT=1 passes |
| 3 | ML runtime path | All Python from monorepo | ⚠️ After Wave 2 | Wave 2 | No `greenhouse/repo` in shell scripts; PREDICT_LIMIT=1 passes from monorepo |
| 4 | Storage abstraction | Wire `get_storage_backend()` | ⚠️ After Wave 3 | Wave 3 | Predict output matches baseline; STORAGE_BACKEND=local works |
| 5 | Frontend + backend | Docker mounts monorepo | ⚠️ After Wave 1 | Wave 1 | Containers healthy; code changes in monorepo reflected live |
| 6 | SQL/cron/deploy norm. | All infra defs in monorepo | ⚠️ After Wave 5 | Wave 5 | Compose in monorepo; B11 documented; sql/ complete |
| 7 | Client-runtime bootstrap | Local runtime skeleton + test | ⚠️ After Wave 4 | Wave 4 | STORAGE_BACKEND=local predict passes; client-runtime/ structure done |
| 8 | Legacy deprecation | Archive all legacy roots | ⚠️ After 3,4,5,6 | Waves 3–6 | No live service references any archived path |

---

## 5. Detailed wave plan

---

### Wave 0 — Production stabilization and freeze

#### Objective
Remove two active production hazards and establish a documented baseline. Zero code changes. Operates entirely on pg_cron config and a file deletion.

#### Changes included
- Disable pg_cron jobs 30, 38, 39
- Delete `lovabel .env corretto.json` from both repos
- Rotate `VITE_SUPABASE_PUBLISHABLE_KEY`; update `/opt/greenbrain/frontend/.env`; restart `gb_v2_frontend`
- Write `docs/migration/freeze-baseline.md`

#### Changes explicitly excluded
- No Python, shell, unit file, or Docker changes

#### Preconditions
- Access to Supabase dashboard (pg_cron disable + key rotation)
- Confirm jobs 11, 29, 37 are active and will cover ETL after disabling 30/38/39

#### Actions

1. Verify before disabling:
   ```sql
   SELECT jobid, schedule, command FROM cron.job WHERE jobid IN (30, 38, 39);
   ```

2. Disable:
   ```sql
   SELECT cron.unschedule(30);
   SELECT cron.unschedule(38);
   SELECT cron.unschedule(39);
   ```

3. Confirm remaining ETL coverage:
   ```sql
   SELECT jobid, schedule, command FROM cron.job WHERE jobid IN (11, 29, 37);
   ```

4. Delete credential files:
   ```bash
   find /opt/greenhouse /opt/greenbrain-platform -name "lovabel .env corretto.json" -delete
   ```

5. Rotate `VITE_SUPABASE_PUBLISHABLE_KEY` in Supabase dashboard → update `/opt/greenbrain/frontend/.env` → `docker restart gb_v2_frontend`.

6. Smoke test login on frontend.

7. Write `docs/migration/freeze-baseline.md` with `systemctl list-timers`, `docker ps` output, and freeze rules from `source-of-truth.md § 3. Freeze rules`.

#### Validation
```bash
# Jobs gone:
psql $DATABASE_URL -c "SELECT COUNT(*) FROM cron.job WHERE schedule = '* * * * *';"
# Expect: 0

systemctl list-timers --all | grep gh-    # 6 timers active
docker ps --format "{{.Names}}: {{.Status}}"  # 6 containers Up
curl -s -o /dev/null -w "%{http_code}" http://localhost:8082  # 200
```

#### Rollback
- pg_cron: `SELECT cron.schedule(...)` to re-add (only if ETL stops — jobs 11/29/37 provide full coverage)
- Vite key: generate another rotation in Supabase; update `.env`

#### Risks
- Rotating the Vite publishable key logs out all active sessions. Coordinate timing.
- Raw data that arrives outside 09:00–12:00 or 19:00–23:00 UTC will miss the ETL window after removing jobs 30/38/39. Assess whether this window covers all real data arrival times before proceeding.

#### Exit criteria
- `SELECT COUNT(*) FROM cron.job WHERE schedule = '* * * * *'` = 0
- Credential files absent (`find /opt/greenhouse /opt/greenbrain-platform -name "lovabel*"` = no output)
- All 6 timers `active (waiting)`, all 6 containers `Up`
- `freeze-baseline.md` committed

#### Deliverables
- `docs/migration/freeze-baseline.md`

---

### Wave 1 — Repo canonicalization and documentation

#### Objective
Zero runtime changes. Establish correct file structure: SQL in the right place, `.gitignore` protecting binary artifacts, structural cleanup of safe-to-remove artifacts.

#### Changes included
- Export Supabase schema → `sql/schema/supabase-schema.sql`
- Create `sql/migrations/` and copy 8 migration files (numbered 001–008)
- Write `sql/cron/pg_cron_canonical.sql` (10 intended jobs)
- Write `sql/README.md`
- Add `.gitignore` entries: `parquet_cache/`, `models_v4/`, `priors_cache/`, `*.bak*`, `__pycache__/`, `.env` (in apps dirs)
- Delete 9 `.bak*` files from `/etc/systemd/system/`
- Delete `config.py.bak` and `ops.py.bak` from `apps/backend/`
- Delete duplicate `models_v4_backup/*.tgz` from `apps/ml-worker/`
- Flatten `infra/systemd/current/` → `infra/systemd/`; write `infra/systemd/install.sh`
- Copy `/opt/greenbrain-v2/docs/` → `docs/archive/greenbrain-v2/`
- Copy `.env.example` from `greenbrain-v2/backend/` → `apps/backend/`

#### Changes explicitly excluded
- No live unit files changed (only `.bak*` deletions from `/etc/systemd/system/`)
- No Python, shell, env content changes
- Do not move or touch `/opt/greenhouse/repo/jobs/migrations/` (frozen legacy)

#### Actions

1. Export schema:
   ```bash
   mkdir -p /opt/greenbrain-platform/sql/schema
   pg_dump "$DATABASE_URL" --schema-only --no-owner --no-acl \
     -f /opt/greenbrain-platform/sql/schema/supabase-schema.sql
   wc -l /opt/greenbrain-platform/sql/schema/supabase-schema.sql  # must be > 1000 lines
   ```

2. Create and populate `sql/migrations/`:
   ```bash
   mkdir -p /opt/greenbrain-platform/sql/migrations
   i=1
   for f in $(ls /opt/greenbrain-platform/apps/ml-worker/jobs/migrations/blocco_*.sql | sort); do
     cp "$f" "/opt/greenbrain-platform/sql/migrations/$(printf '%03d' $i)_$(basename $f)"
     ((i++))
   done
   ```

3. Write `sql/cron/pg_cron_canonical.sql` — extract from Supabase:
   ```bash
   mkdir -p /opt/greenbrain-platform/sql/cron
   psql "$DATABASE_URL" -c \
     "SELECT 'SELECT cron.schedule(''' || jobname || ''', ''' || schedule || ''', $$ ' || command || ' $$);' FROM cron.job WHERE jobid NOT IN (30,38,39) ORDER BY jobid;" \
     -t > /opt/greenbrain-platform/sql/cron/pg_cron_canonical.sql
   ```

4. Update `.gitignore` at monorepo root and `apps/ml-worker/`:
   ```
   parquet_cache/
   models_v4/
   priors_cache/
   *.bak
   *.bak_*
   __pycache__/
   *.pyc
   apps/frontend/.env
   apps/backend/.env
   infra/docker/.env
   ```

5. Cleanup:
   ```bash
   rm /etc/systemd/system/gh-*.bak*
   rm /opt/greenbrain-platform/apps/backend/app/core/config.py.bak
   rm /opt/greenbrain-platform/apps/backend/app/api/v1/ops.py.bak
   rm /opt/greenbrain-platform/apps/ml-worker/models_v4_backup/models_v4_20260221_092011.tgz
   ```

6. Flatten systemd directory:
   ```bash
   mv /opt/greenbrain-platform/infra/systemd/current/* \
      /opt/greenbrain-platform/infra/systemd/
   rmdir /opt/greenbrain-platform/infra/systemd/current/
   ```

7. Write `infra/systemd/install.sh` (copies units to `/etc/systemd/system/`, runs `daemon-reload`).

8. Archive old docs and copy `.env.example`:
   ```bash
   mkdir -p /opt/greenbrain-platform/docs/archive
   cp -r /opt/greenbrain-v2/docs/ /opt/greenbrain-platform/docs/archive/greenbrain-v2/
   cp /opt/greenbrain-v2/backend/.env.example /opt/greenbrain-platform/apps/backend/
   ```

#### Validation
```bash
ls /opt/greenbrain-platform/sql/schema/supabase-schema.sql    # must exist, >0 size
ls /opt/greenbrain-platform/sql/migrations/ | wc -l           # expect 8
ls /opt/greenbrain-platform/sql/cron/pg_cron_canonical.sql    # must exist
find /etc/systemd/system -name "*.bak*" | wc -l               # expect 0
ls /opt/greenbrain-platform/infra/systemd/ | grep -v current  # 12 unit files
systemctl list-timers --all | grep gh-                         # 6 timers still active
docker ps --format "{{.Names}}: {{.Status}}"                   # 6 containers Up
```

#### Rollback
All deletions are of non-runtime files. No rollback risk. Restore any deleted `.bak` from git or legacy repo if needed.

#### Exit criteria
- `sql/schema/supabase-schema.sql` > 100KB
- `sql/migrations/` has 8 numbered files
- `sql/cron/pg_cron_canonical.sql` has 10 job definitions
- No `.bak*` in `/etc/systemd/system/`
- `infra/systemd/` has 12 unit files directly (no `current/` subdir)
- All timers and containers still healthy

#### Deliverables
- `sql/schema/supabase-schema.sql`
- `sql/migrations/001–008_*.sql`
- `sql/cron/pg_cron_canonical.sql`
- `sql/README.md`
- `infra/systemd/install.sh`
- `docs/archive/greenbrain-v2/`

---

### Wave 2 — Env/config and CLI consolidation

#### Objective
Establish one env loading system (`load_env.sh` + `infra/env/`) for all 6 ML systemd services and one CLI bin path (`infra/scripts/bin/`). After this wave, `/opt/greenhouse/.env` is referenced by nothing in production.

#### Changes included
- Add compatibility aliases to `infra/env/dev.env`: `SUPABASE_DB_*`, `SUPABASE_KEY`
- Migrate `gh-train-biweekly-all.service`: remove `EnvironmentFile=/opt/greenhouse/.env`; add `load_env.sh` call; update ExecStartPost bin path
- Migrate `gh-train-quarterly.service`: same
- Remove `/opt/greenhouse/bin/` from `$PATH`
- `systemctl daemon-reload`

#### Changes explicitly excluded
- No `WorkingDirectory` changes (Wave 3)
- No Python changes
- Do not modify `/opt/greenhouse/.env` itself

#### Preconditions
- Wave 0 complete
- Diff `/opt/greenhouse/.env` vs `infra/env/dev.env` — all variables present or aliased before proceeding
- biweekly/quarterly NOT scheduled to run during this wave window

#### Actions

1. Diff env files:
   ```bash
   grep -E '^[A-Z_]+=' /opt/greenhouse/.env | cut -d= -f1 | sort > /tmp/legacy_vars.txt
   grep -E '^[A-Z_]+=' /opt/greenbrain-platform/infra/env/dev.env | cut -d= -f1 | sort > /tmp/new_vars.txt
   diff /tmp/legacy_vars.txt /tmp/new_vars.txt
   ```
   Add any missing variables to `dev.env` before continuing.

2. Add aliases to `infra/env/dev.env`:
   ```bash
   cat >> /opt/greenbrain-platform/infra/env/dev.env << 'EOF'

   # Compatibility: export_features_dense.py uses SUPABASE_DB_* naming
   SUPABASE_DB_HOST=${PG_HOST}
   SUPABASE_DB_PORT=${PG_PORT}
   SUPABASE_DB_NAME=${PG_DB}
   SUPABASE_DB_USER=${PG_USER}
   SUPABASE_DB_PASSWORD=${PG_PASSWORD}

   # Legacy alias used by data_access_v1.py
   SUPABASE_KEY=${SUPABASE_SERVICE_ROLE_KEY}
   EOF
   ```

3. Edit `/etc/systemd/system/gh-train-biweekly-all.service`:
   - Remove: `EnvironmentFile=/opt/greenhouse/.env`
   - Prefix ExecStart with: `source /opt/greenbrain-platform/infra/scripts/load_env.sh &&`
   - Update ExecStartPost: `/opt/greenhouse/bin/gh-sync-local-artifacts` → `/opt/greenbrain-platform/infra/scripts/bin/gh-sync-local-artifacts`

4. Apply same to `gh-train-quarterly.service`.

5. Copy updated units to monorepo `infra/systemd/`.

6. `systemctl daemon-reload`

7. Remove legacy bin from PATH:
   ```bash
   grep -r "greenhouse/bin" /etc/environment /etc/profile.d/ ~/.bashrc 2>/dev/null
   # Edit the relevant file to remove the line
   ```

8. Verify PATH resolution:
   ```bash
   which gh-predict-all  # must be infra/scripts/bin/
   which gh-sync-local-artifacts  # must be infra/scripts/bin/
   ```

9. Test biweekly service starts with new env:
   ```bash
   TRAIN_LIMIT=1 systemctl start gh-train-biweekly-all
   journalctl -u gh-train-biweekly-all -n 30 --no-pager
   ```

#### Validation
```bash
source /opt/greenbrain-platform/infra/scripts/load_env.sh
echo $SUPABASE_DB_HOST   # non-empty
echo $SUPABASE_KEY        # non-empty

systemctl show gh-train-biweekly-all --property=EnvironmentFiles
# expect empty or only infra/env path

which gh-predict-all      # infra/scripts/bin path
```

#### Rollback
- Restore `EnvironmentFile=/opt/greenhouse/.env` line in unit files; `daemon-reload`
- Re-add `/opt/greenhouse/bin/` to PATH
- Remove appended aliases from `dev.env`

#### Risks
- Shell variable expansion in `dev.env` (`${PG_HOST}`) only works if `load_env.sh` uses `source`. Verify before appending.
- biweekly/quarterly cannot be fully cycle-tested. Use `TRAIN_LIMIT=1` manual start as proxy.

#### Exit criteria
- `grep EnvironmentFile /etc/systemd/system/gh-train-biweekly-all.service` returns nothing (or only monorepo path)
- `which gh-predict-all` returns monorepo bin path
- `TRAIN_LIMIT=1 systemctl start gh-train-biweekly-all` exits cleanly
- `source infra/env/dev.env && echo $SUPABASE_DB_HOST` returns non-empty

#### Deliverables
- Updated `infra/env/dev.env`
- Updated `infra/systemd/gh-train-biweekly-all.service`
- Updated `infra/systemd/gh-train-quarterly.service`

---

### Wave 3 — ML runtime path unification

#### Objective
All 6 systemd ML services execute Python from `/opt/greenbrain-platform/apps/ml-worker/`. Shell entry scripts stop redirecting to `/opt/greenhouse/repo`. Legacy repo frozen read-only. Services migrated one at a time.

**Order:** parquet-export → train-missing → predict-all → biweekly → quarterly (refresh-registry already done).

#### Changes included
- Add `GH_REPO_DIR=/opt/greenbrain-platform/apps/ml-worker` to `infra/env/dev.env`
- Fix `run_daily_parquet_batches.sh`: replace `PROJECT_DIR="/opt/greenhouse/repo/..."` with `PROJECT_DIR="${GH_REPO_DIR}/jobs/parquet_export"`
- Fix `run_train_missing.sh`: replace `cd /opt/greenhouse/repo` with `cd $GH_REPO_DIR`
- Fix `run_predict_all.sh`: same replacement
- Update `WorkingDirectory` in `gh-train-biweekly-all.service` and `gh-train-quarterly.service`
- Freeze `/opt/greenhouse/repo/` as read-only
- `systemctl daemon-reload` after unit changes

#### Changes explicitly excluded
- Do not modify any `.py` files (Wave 4)
- Do not delete `/opt/greenhouse/repo/`
- Do not change DB connection strings

#### Preconditions
- Wave 2 complete; `GH_REPO_DIR` not yet set (will be added in this wave)
- Confirm monorepo and legacy Python files are identical: `diff -rq /opt/greenhouse/repo/ /opt/greenbrain-platform/apps/ml-worker/ --exclude="*.bak*" --exclude="parquet_cache" --exclude="models_v4"`
- Confirm venv works from monorepo path: `source /opt/greenhouse/venv/bin/activate && cd /opt/greenbrain-platform/apps/ml-worker && python3 -c "from jobs.predict_all import *"`

#### Actions

1. Add `GH_REPO_DIR` to `dev.env`:
   ```
   GH_REPO_DIR=/opt/greenbrain-platform/apps/ml-worker
   ```

2. Fix `run_daily_parquet_batches.sh` — replace hardcoded path:
   ```bash
   # old: PROJECT_DIR="/opt/greenhouse/repo/jobs/parquet_export"
   # new:
   PROJECT_DIR="${GH_REPO_DIR}/jobs/parquet_export"
   ```

3. Fix `run_train_missing.sh` and `run_predict_all.sh`:
   ```bash
   # old: cd /opt/greenhouse/repo
   # new:
   cd $GH_REPO_DIR
   ```

4. Test parquet-export (use pre-check only, not full export):
   ```bash
   systemctl start gh-parquet-export
   journalctl -u gh-parquet-export -n 30 --no-pager | grep -E "ERROR|PROJECT_DIR|Working"
   ```

5. Test train-missing with limit:
   ```bash
   TRAIN_LIMIT=1 systemctl start gh-train-missing
   journalctl -u gh-train-missing -n 50 --no-pager
   ```

6. Test predict-all with limit:
   ```bash
   PREDICT_LIMIT=1 systemctl start gh-predict-all
   journalctl -u gh-predict-all -n 50 --no-pager
   ```
   Confirm new row in `greenhouse_forecast_results_v2`.

7. Update biweekly/quarterly `WorkingDirectory` in unit files; `systemctl daemon-reload`.

8. Test quarterly with limit:
   ```bash
   TRAIN_LIMIT=1 systemctl start gh-train-quarterly
   journalctl -u gh-train-quarterly -n 30 --no-pager
   ```

9. Freeze legacy repo:
   ```bash
   chmod -R a-w /opt/greenhouse/repo/
   ```

10. Copy updated unit files to `infra/systemd/`.

#### Validation
```bash
# No legacy path in shell scripts:
grep -r "greenhouse/repo" /opt/greenbrain-platform/apps/ml-worker/jobs/
# Expected: no output

# Confirm Python runs from monorepo (check a recent log):
journalctl -u gh-predict-all --since "1h ago" | grep -i "working\|project_dir\|greenhouse/repo"

# New forecast row:
psql $DATABASE_URL -c "
  SELECT famiglia_slug, MAX(created_at) FROM greenhouse_forecast_results_v2
  GROUP BY famiglia_slug ORDER BY 2 DESC LIMIT 3;"
```

#### Rollback
- Shell scripts: restore the `cd /opt/greenhouse/repo` line
- Unit files: restore `WorkingDirectory` to `/opt/greenhouse/repo`
- Legacy freeze: `chmod -R u+w /opt/greenhouse/repo/`
- `systemctl daemon-reload`

#### Risks
- **`PYTHONPATH` implicit dependency:** If any script relied on the repo root being on `sys.path` implicitly, imports may fail. Test all 4 core import chains before the daily timer fires.
- **biweekly/quarterly full cycle untestable** until next eligible date — `TRAIN_LIMIT=1` is required proxy.

#### Exit criteria
- `grep -r "greenhouse/repo" /opt/greenbrain-platform/apps/ml-worker/jobs/` returns nothing
- `PREDICT_LIMIT=1` test produces new rows in `greenhouse_forecast_results_v2`
- `journalctl -u gh-predict-all` shows no reference to `/opt/greenhouse/repo`
- `/opt/greenhouse/repo/` is read-only
- All 6 timers `active (waiting)`

#### Deliverables
- Updated `run_predict_all.sh`, `run_train_missing.sh`, `run_daily_parquet_batches.sh`
- Updated `infra/env/dev.env` (`GH_REPO_DIR`)
- Updated `infra/systemd/gh-train-biweekly-all.service`, `gh-train-quarterly.service`
- Read-only `/opt/greenhouse/repo/`

---

### Wave 4 — Storage abstraction activation

#### Objective
Replace the 4 files that call the Supabase SDK directly with the `.bak_phase2b/2c` versions that use `get_storage_backend()`. Validate with `STORAGE_BACKEND=supabase` first (no behavior change), then prove `STORAGE_BACKEND=local` for the client-runtime path. Delete `.bak` files after both tests pass.

#### Changes included
- Apply `data_access_v1.py.bak_phase2b_fix` → `data_access_v1.py`
- Apply `export_features_dense.py.bak_phase2b` → `export_features_dense.py`
- Apply `upload_priors_to_supabase.py.bak_phase2c` → `upload_priors_to_supabase.py`
- Apply `download_priors_from_supabase.py.bak_phase2c` → `download_priors_from_supabase.py`
- Confirm `STORAGE_BACKEND=supabase` in `infra/env/dev.env`
- Test predict output matches pre-Wave 4 baseline
- Test `STORAGE_BACKEND=local` for one family
- Delete all `.bak_phase2*` files

#### Changes explicitly excluded
- Do not replace `spaces_io.py` / `ensure_model_bundle.py` with S3StorageBackend (separate sub-task, not blocking)
- Do not change SQL, systemd, or Docker

#### Preconditions
- Wave 3 complete — monorepo is the live Python source
- Review `.bak_phase2b_fix` file manually before applying; confirm it imports `get_storage_backend` and sets `STORAGE_BACKEND` env var as the selector
- `STORAGE_BACKEND` and `LOCAL_STORAGE_ROOT` present in `infra/env/dev.env`
- Confirm `storage/backend.py` `get_storage_backend()` default is `supabase` (not `local`) when `STORAGE_BACKEND` is unset

#### Actions

1. Capture baseline forecast for one family:
   ```bash
   psql $DATABASE_URL -c "
     SELECT famiglia_slug, forecast_date, q50
     FROM greenhouse_forecast_results_v2
     WHERE famiglia_slug = '<test-slug>'
     ORDER BY forecast_date LIMIT 30;" > /tmp/baseline_predict.txt
   ```

2. Back up the 4 files before replacing:
   ```bash
   cd /opt/greenbrain-platform/apps/ml-worker
   for f in data_access_v1.py \
             jobs/parquet_export/export_features_dense.py \
             jobs/upload_priors_to_supabase.py \
             jobs/download_priors_from_supabase.py; do
     cp "$f" "${f}.orig_wave4"
   done
   ```

3. Apply the 4 replacements:
   ```bash
   cp data_access_v1.py.bak_phase2b_fix data_access_v1.py
   cp jobs/parquet_export/export_features_dense.py.bak_phase2b \
      jobs/parquet_export/export_features_dense.py
   cp jobs/upload_priors_to_supabase.py.bak_phase2c \
      jobs/upload_priors_to_supabase.py
   cp jobs/download_priors_from_supabase.py.bak_phase2c \
      jobs/download_priors_from_supabase.py
   ```

4. Verify no direct Supabase SDK import in the 4 files:
   ```bash
   grep -n "from supabase import" \
     data_access_v1.py \
     jobs/parquet_export/export_features_dense.py \
     jobs/upload_priors_to_supabase.py \
     jobs/download_priors_from_supabase.py
   # Expected: no output
   ```

5. Test imports:
   ```bash
   source /opt/greenhouse/venv/bin/activate
   STORAGE_BACKEND=supabase python3 -c "from data_access_v1 import *; print('OK')"
   ```

6. Run predict with supabase backend, compare to baseline:
   ```bash
   STORAGE_BACKEND=supabase PREDICT_LIMIT=1 systemctl start gh-predict-all
   journalctl -u gh-predict-all -n 50 --no-pager | grep -E "ERROR|backend|storage"
   psql $DATABASE_URL -c "
     SELECT famiglia_slug, forecast_date, q50
     FROM greenhouse_forecast_results_v2
     WHERE famiglia_slug = '<test-slug>'
     ORDER BY forecast_date LIMIT 30;" > /tmp/after_predict.txt
   diff /tmp/baseline_predict.txt /tmp/after_predict.txt
   ```

7. Test local backend with a sample family:
   ```bash
   mkdir -p $LOCAL_STORAGE_ROOT/features_dense/v1
   cp -r $PARQUET_CACHE_DIR/year=2025/famiglia_slug=<test-slug>/ \
         $LOCAL_STORAGE_ROOT/features_dense/v1/
   STORAGE_BACKEND=local PREDICT_LIMIT=1 systemctl start gh-predict-all
   journalctl -u gh-predict-all -n 50 --no-pager
   ```

8. If both tests pass, delete `.bak` files:
   ```bash
   find /opt/greenbrain-platform/apps/ml-worker -name "*.bak_phase2*" -delete
   find /opt/greenbrain-platform/apps/ml-worker -name "*.orig_wave4" -delete
   ```

#### Validation
```bash
grep -c "get_storage_backend" apps/ml-worker/data_access_v1.py  # >= 1
grep "from supabase import" apps/ml-worker/data_access_v1.py    # no output
journalctl -u gh-predict-all --since "1h ago" | grep -i "storage backend"
find apps/ml-worker -name "*.bak_phase2*" | wc -l   # expect 0
```

#### Rollback
```bash
cd /opt/greenbrain-platform/apps/ml-worker
cp data_access_v1.py.orig_wave4 data_access_v1.py
cp jobs/parquet_export/export_features_dense.py.orig_wave4 \
   jobs/parquet_export/export_features_dense.py
# repeat for the other 2 files
```

#### Risks
- **Silent wrong backend:** If `STORAGE_BACKEND` is not exported into the process environment, `get_storage_backend()` may silently default to an unexpected backend. Confirm `load_env.sh` exports all variables (`export VAR=value`, not just `VAR=value`).
- **Float divergence in forecast output:** Parquet column ordering may differ across backends causing different row order fed to the model. Accept tolerance-based diff; reject only if q50 values differ by > 0.1%.

#### Exit criteria
- `grep "from supabase import" data_access_v1.py` = no output
- `STORAGE_BACKEND=supabase` predict output matches baseline (within tolerance)
- `STORAGE_BACKEND=local` predict completes without error for ≥ 1 family
- No `.bak_phase2*` files in monorepo
- All 6 timers still `active (waiting)`

#### Deliverables
- Updated `data_access_v1.py`, `export_features_dense.py`, `upload_priors_to_supabase.py`, `download_priors_from_supabase.py`
- `docs/migration/wave4-validation.md` (diff result, backend test results)

---

### Wave 5 — Frontend and backend into monorepo

#### Objective
Docker containers `gb_v2_frontend` and `gb_v2_backend` mount monorepo paths. Code changes to `apps/frontend/` and `apps/backend/` are immediately reflected in running containers.

#### Changes included
- Copy `/opt/greenbrain/frontend/.env` → `apps/frontend/.env` (gitignored)
- Copy `/opt/greenbrain/frontend/supabase/` → `apps/frontend/supabase/`
- Resolve `apps/frontend/` lock file conflict: remove `bun.lock`, `bun.lockb`; keep `package-lock.json`
- Verify `npm install && npm run dev` works in `apps/frontend/`
- Update `docker-compose.base.yml` frontend volume: `/opt/greenbrain/frontend:/app` → `/opt/greenbrain-platform/apps/frontend:/app`
- Update `docker-compose.base.yml` backend volume: `../backend:/app` → `/opt/greenbrain-platform/apps/backend:/app`
- `docker compose up -d --force-recreate gb_v2_frontend gb_v2_backend`

#### Changes explicitly excluded
- Do not redesign auth (Supabase auth stays as-is)
- Do not switch frontend from `npm run dev` to production build (separate decision)
- Do not resolve B11 (DB gap between API and Supabase)
- Do not change nginx config

#### Preconditions
- Wave 1 complete (`.bak` files removed from `apps/backend/`)
- `apps/frontend/.env` copied and verified before any Docker restart
- Confirm `apps/backend/app/` has no import errors: `python3 -m py_compile app/main.py` from that directory

#### Actions

1. Copy frontend env and supabase config:
   ```bash
   cp /opt/greenbrain/frontend/.env /opt/greenbrain-platform/apps/frontend/.env
   cp -r /opt/greenbrain/frontend/supabase/ /opt/greenbrain-platform/apps/frontend/supabase/
   ```

2. Resolve lock files:
   ```bash
   cd /opt/greenbrain-platform/apps/frontend/
   rm -f bun.lock bun.lockb
   npm install
   ```

3. Verify dev server from monorepo (use non-conflicting port):
   ```bash
   cd /opt/greenbrain-platform/apps/frontend/
   timeout 15 npm run dev -- --host 0.0.0.0 --port 8099 &
   sleep 8 && curl -s -o /dev/null -w "%{http_code}" http://localhost:8099
   kill %1 2>/dev/null
   # expect 200
   ```

4. Update `/opt/greenbrain-v2/deploy/docker-compose.base.yml` volumes:
   - Frontend: `/opt/greenbrain/frontend:/app` → `/opt/greenbrain-platform/apps/frontend:/app`
   - Backend: `../backend:/app` → `/opt/greenbrain-platform/apps/backend:/app`

5. Recreate the two containers:
   ```bash
   cd /opt/greenbrain-v2/deploy/
   docker compose -f docker-compose.base.yml -f docker-compose.dev.yml \
     up -d --force-recreate gb_v2_frontend gb_v2_backend
   ```

6. Smoke tests:
   ```bash
   sleep 10
   curl -s -o /dev/null -w "%{http_code}" http://localhost:8082     # frontend nginx
   curl -s -o /dev/null -w "%{http_code}" http://localhost:8002/api/v1/system/health
   ```

#### Validation
```bash
docker inspect gb_v2_frontend | python3 -c \
  "import sys,json; m=json.load(sys.stdin); print(m[0]['HostConfig']['Binds'])"
# must show /opt/greenbrain-platform/apps/frontend

docker inspect gb_v2_backend | python3 -c \
  "import sys,json; m=json.load(sys.stdin); print(m[0]['HostConfig']['Binds'])"
# must show /opt/greenbrain-platform/apps/backend

curl http://localhost:8002/api/v1/system/health  # 200
# Manual: make a small change in apps/frontend/src/ and verify it appears in browser
```

#### Rollback
```bash
# Revert the two volume lines in docker-compose.base.yml, then:
cd /opt/greenbrain-v2/deploy/
docker compose -f docker-compose.base.yml -f docker-compose.dev.yml \
  up -d --force-recreate gb_v2_frontend gb_v2_backend
```

#### Risks
- **Missing `node_modules` in container:** Container mounts source but `node_modules` may not exist inside the container if the entrypoint does not run `npm install` first. Check container CMD/entrypoint before proceeding.
- **Frontend `.env` forgotten:** If `.env` is absent at mount time, Vite builds with undefined `VITE_SUPABASE_URL` — auth silently fails. Verify file exists before Docker restart.

#### Exit criteria
- `docker inspect gb_v2_frontend` shows monorepo bind mount
- `docker inspect gb_v2_backend` shows monorepo bind mount
- Frontend loads in browser; login works
- `GET /api/v1/system/health` returns 200
- Code change in `apps/frontend/src/` reflects in running container (HMR)

#### Deliverables
- `apps/frontend/.env` (gitignored)
- `apps/frontend/supabase/` (added)
- Updated `docker-compose.base.yml` (still in `/opt/greenbrain-v2/deploy/` for now)
- `docs/migration/wave5-validation.md`

---

### Wave 6 — SQL/cron versioning and deploy normalization

#### Objective
Move Docker compose files into the monorepo. Write a SQL migration runner. Formally document the API/DB architectural gap (B11) as a decision item. Archive `/opt/greenbrain-v2/deploy/`.

#### Changes included
- Copy `docker-compose.*.yml` and `.env.client` to `infra/docker/`
- Update volume mounts in `infra/docker/docker-compose.base.yml` (already correct from Wave 5)
- Write `sql/migrate.sh` runner
- Write `infra/docker/README.md`
- Write `docs/architecture/db-gap.md` documenting B11 and resolution options
- Write `ARCHIVED_WAVE6.md` in `/opt/greenbrain-v2/deploy/`

#### Changes explicitly excluded
- Do not resolve B11 itself (requires architecture decision: logical replication vs. migrate API to Supabase vs. nightly sync)
- Do not delete `/opt/greenbrain-v2/deploy/`
- Do not restart any containers

#### Preconditions
- Wave 5 complete — Docker already serving from monorepo paths

#### Actions

1. Create and populate `infra/docker/`:
   ```bash
   mkdir -p /opt/greenbrain-platform/infra/docker/
   cp /opt/greenbrain-v2/deploy/docker-compose.base.yml \
      /opt/greenbrain-v2/deploy/docker-compose.dev.yml \
      /opt/greenbrain-v2/deploy/docker-compose.client.yml \
      /opt/greenbrain-v2/deploy/.env.client \
      /opt/greenbrain-platform/infra/docker/
   # Copy live .env (gitignored):
   cp /opt/greenbrain-v2/deploy/.env /opt/greenbrain-platform/infra/docker/.env
   ```

2. Update volume mounts in `infra/docker/docker-compose.base.yml` to match Wave 5 changes (monorepo paths).

3. Write `sql/migrate.sh`:
   ```bash
   #!/bin/bash
   set -e
   DIR="$(cd "$(dirname "$0")/migrations" && pwd)"
   for f in "$DIR"/[0-9]*.sql; do
     echo "→ $f"
     psql "${DATABASE_URL:-$PG_URL}" -f "$f"
   done
   echo "All migrations complete."
   ```

4. Write `infra/docker/README.md` documenting the compose stack, port assignments, and volume locations.

5. Write `docs/architecture/db-gap.md` documenting:
   - The gap: API reads `gb_v2_postgres` (local Docker); ML writes Supabase cloud
   - Impact: frontend may show data that is days behind ML output
   - Resolution options: (a) logical replication Supabase → local PG, (b) migrate FastAPI to read Supabase directly, (c) nightly `pg_dump | psql` sync
   - Decision required from: engineering lead

6. Mark legacy deploy dir as archived:
   ```bash
   cat > /opt/greenbrain-v2/deploy/ARCHIVED_WAVE6.md << 'EOF'
   # Archived — Wave 6 (2026-03-27)
   Compose files now live in /opt/greenbrain-platform/infra/docker/
   This directory is kept as a reference. Do not run compose from here.
   EOF
   ```

#### Validation
```bash
ls /opt/greenbrain-platform/infra/docker/     # compose files present
ls /opt/greenbrain-platform/sql/migrate.sh    # exists
bash /opt/greenbrain-platform/sql/migrate.sh --dry-run 2>/dev/null || echo "needs --dry-run support"
ls /opt/greenbrain-platform/docs/architecture/db-gap.md

# All containers still healthy:
docker ps --format "{{.Names}}: {{.Status}}"
```

#### Exit criteria
- `infra/docker/` has 3 compose files and `.env.client`
- `sql/migrate.sh` is executable
- `docs/architecture/db-gap.md` exists
- `ARCHIVED_WAVE6.md` in `/opt/greenbrain-v2/deploy/`
- All 6 containers still `Up`

#### Deliverables
- `infra/docker/docker-compose.base.yml`, `.dev.yml`, `.client.yml`
- `infra/docker/README.md`
- `sql/migrate.sh`
- `docs/architecture/db-gap.md`
- `/opt/greenbrain-v2/deploy/ARCHIVED_WAVE6.md`

---

### Wave 7 — Client-runtime bootstrap

#### Objective
Create the minimum viable client-installable package skeleton. Prove `STORAGE_BACKEND=local` end-to-end. Define the contract for `install.sh`, `update.sh`, and `doctor.sh`. This wave does not produce a fully installable product — it proves the local runtime path works and creates the structural skeleton.

#### Changes included
- Create `client-runtime/` directory with subdirectories
- Write `client-runtime/.env.client.template` (all required vars documented)
- Write `client-runtime/install.sh` skeleton
- Write `client-runtime/update.sh` skeleton (downloads parquet + model bundles to `LOCAL_STORAGE_ROOT`)
- Write `client-runtime/doctor.sh` skeleton (checks env, venv, DB, storage)
- Copy `infra/docker/docker-compose.client.yml` to `client-runtime/`
- Populate `LOCAL_STORAGE_ROOT` with sample family parquet
- Run end-to-end predict in local mode for ≥ 1 family

#### Changes explicitly excluded
- Do not implement full production packaging (separate project phase)
- Do not migrate auth from Supabase to local JWT
- Do not bundle the Python venv inside `client-runtime/` yet

#### Preconditions
- Wave 4 complete — `STORAGE_BACKEND=local` tested in isolation
- Wave 3 complete — monorepo is live ML runtime
- `LOCAL_STORAGE_ROOT` set in `infra/env/dev.env` or `infra/env/client.env`

#### Actions

1. Create structure:
   ```bash
   mkdir -p /opt/greenbrain-platform/client-runtime/scripts
   ```

2. Write `client-runtime/.env.client.template` with every required variable documented:
   ```
   # Storage
   STORAGE_BACKEND=local
   LOCAL_STORAGE_ROOT=/opt/greenbrain-client/storage

   # Database (local PostgreSQL)
   PG_HOST=localhost
   PG_PORT=5432
   PG_DB=greenbrain_client
   PG_USER=greenbrain
   PG_PASSWORD=changeme

   # Compatibility aliases
   SUPABASE_DB_HOST=${PG_HOST}
   # ... (full list from infra/env/base.env, redacted secrets)
   ```

3. Write `client-runtime/install.sh` skeleton:
   - Creates `LOCAL_STORAGE_ROOT` directories
   - Creates local PostgreSQL DB and user
   - Installs Python venv from `requirements.txt`
   - Runs `doctor.sh` at end

4. Write `client-runtime/update.sh` skeleton:
   - Downloads latest parquet from remote (`STORAGE_BACKEND=supabase` pull mode, or rsync)
   - Downloads latest model bundles from DO Spaces
   - Writes to `LOCAL_STORAGE_ROOT`

5. Write `client-runtime/doctor.sh` skeleton:
   - Checks: Python imports, DB connection, `LOCAL_STORAGE_ROOT` exists and readable, env vars set, storage backend responds

6. Populate test local storage:
   ```bash
   mkdir -p $LOCAL_STORAGE_ROOT/features_dense/v1
   cp -r $PARQUET_CACHE_DIR/year=2025/famiglia_slug=<test-slug>/ \
         $LOCAL_STORAGE_ROOT/features_dense/v1/
   ```

7. Run end-to-end predict in local mode:
   ```bash
   source /opt/greenbrain-platform/client-runtime/.env.client.template
   STORAGE_BACKEND=local PREDICT_LIMIT=1 \
     python3 -m jobs.predict_all
   journalctl -u gh-predict-all -n 30 --no-pager || \
     python3 -m jobs.predict_all 2>&1 | tail -20
   ```

#### Exit criteria
- `client-runtime/` structure present with all 4 script skeletons
- `.env.client.template` has all required variables
- `STORAGE_BACKEND=local` predict produces output for ≥ 1 family without error
- `doctor.sh` runs without error on development server

#### Deliverables
- `client-runtime/install.sh`
- `client-runtime/update.sh`
- `client-runtime/doctor.sh`
- `client-runtime/.env.client.template`
- `client-runtime/docker-compose.client.yml`
- `docs/migration/wave7-local-mode-validation.md`

---

### Wave 8 — Final deprecation of legacy paths

#### Objective
Archive all legacy source directories. After this wave, no live service references any path outside `/opt/greenbrain-platform`. Directories are **renamed** (not deleted) to `<name>_archived_YYYYMMDD`.

#### Mandatory checklist before executing any step in this wave

Every condition below must be confirmed with evidence before the corresponding archive is done:

| Path to archive | Required condition | Evidence command |
|----------------|-------------------|-----------------|
| `/opt/greenhouse/repo/` | All 6 systemd services run Python from monorepo for ≥ 7 consecutive days | `journalctl -u gh-predict-all --since "7 days ago" \| grep greenhouse/repo` → no output |
| `/opt/greenhouse/repo/` | `gh-train-biweekly-all` has completed at least one full run from monorepo | `journalctl -u gh-train-biweekly-all --since "60 days ago" \| grep "monorepo\|WorkingDirectory"` |
| `/opt/greenhouse/.env` | No systemd service references it | `grep -r "greenhouse/.env" /etc/systemd/system/` → no output |
| `/opt/greenhouse/bin/` | Not in PATH; no systemd ExecStart/ExecStartPost references it | `grep -r "greenhouse/bin" /etc/systemd/system/` → no output |
| `/opt/greenbrain/frontend/` | Docker `gb_v2_frontend` has mounted monorepo path for ≥ 3 days | `docker inspect gb_v2_frontend \| grep Binds` shows monorepo path |
| `/opt/greenbrain-v2/backend/` | Docker `gb_v2_backend` has mounted monorepo path for ≥ 3 days | `docker inspect gb_v2_backend \| grep Binds` shows monorepo path |
| `/opt/greenbrain-v2/deploy/` | `infra/docker/` compose files confirmed live | `ARCHIVED_WAVE6.md` exists in `/opt/greenbrain-v2/deploy/` |

#### Actions (per path, after each condition above is met)

```bash
DATE=$(date +%Y%m%d)

# Archive ML legacy repo (after 7-day clean run from monorepo):
mv /opt/greenhouse/repo /opt/greenhouse/repo_archived_$DATE

# Archive legacy bin (after PATH cleanup confirmed):
mv /opt/greenhouse/bin /opt/greenhouse/bin_archived_$DATE

# Archive legacy frontend (after Docker confirmed on monorepo for 3+ days):
mv /opt/greenbrain/frontend /opt/greenbrain/frontend_archived_$DATE

# Archive legacy backend (after Docker confirmed on monorepo for 3+ days):
mv /opt/greenbrain-v2/backend /opt/greenbrain-v2/backend_archived_$DATE

# Archive legacy deploy (after Wave 6 confirmed complete):
mv /opt/greenbrain-v2/deploy /opt/greenbrain-v2/deploy_archived_$DATE
```

#### Do not delete — retain archived directories until

- First full client-runtime install-from-scratch succeeds (Wave 7 exit criteria met)
- All archived dirs reviewed and confirmed to contain no unique non-recoverable data
- Explicit decision documented in `docs/migration/wave8-archive-log.md`

#### Exit criteria
- `grep -r "/opt/greenhouse/repo" /etc/systemd/system/` → no output
- `grep -r "/opt/greenbrain/frontend" /opt/greenbrain-v2/` → no output (compose updated)
- `grep -r "/opt/greenbrain-v2/backend" /opt/greenbrain-v2/deploy/` → no output
- All 6 containers and all 6 timers still healthy
- `docs/migration/wave8-archive-log.md` written

#### Deliverables
- `docs/migration/wave8-archive-log.md`
- Renamed legacy directories (not deleted)

---

## 6. Dependency graph between waves

```
Wave 0 ─────────────────────────────────────────────────────┐
  (disable pg_cron 30/38/39, delete credential, baseline)   │
                                                             │
Wave 1 ──────────────────────────────────────────────────── │ (parallel)
  (sql/, .gitignore, systemd cleanup, docs archive)         │
                                                             ▼
                                                           Wave 2
                                                   (env consolidation, bin)
                                                             │
                                                             ▼
                                                           Wave 3
                                                   (ML runtime path unification)
                                                             │
                                              ┌──────────────┘
                                              ▼
                                           Wave 4
                                   (storage abstraction wiring)
                                              │
                                              ▼
                                           Wave 7            Wave 5
                                   (client-runtime)    (frontend+backend)
                                              │                │
                                              │                ▼
                                              │             Wave 6
                                              │   (SQL/cron/deploy normalization)
                                              │                │
                                              └───────┬────────┘
                                                      ▼
                                                   Wave 8
                                           (legacy deprecation)
```

**Wave 5 is independent of Waves 2–4** — it only requires Wave 1 (`.bak` cleanup in `apps/backend/`). Frontend and backend migration can proceed in parallel with the ML runtime migration path.

---

## 7. Safe parallel work

The following can be done **at any time** via Windsurf/Cascade without touching production. None of these require a running service to be restarted.

| Work item | What to do | Where |
|-----------|-----------|-------|
| SQL directory structure | Create `sql/migrations/`, `sql/cron/`, `sql/README.md` | Wave 1 actions |
| `.gitignore` cleanup | Add cache dirs and `.bak*` patterns | Wave 1 action 4 |
| Systemd `.bak*` deletion | `rm /etc/systemd/system/gh-*.bak*` | Wave 1 action 5 |
| `apps/backend/` `.bak` deletion | Remove `config.py.bak`, `ops.py.bak` | Wave 1 action 8 |
| Monorepo `.tgz` deletion | Remove duplicate backup archive | Wave 1 action 9 |
| `infra/systemd/` flatten | Move files out of `current/`; write `install.sh` | Wave 1 actions 6–7 |
| `docs/` consolidation | Copy old docs to `docs/archive/` | Wave 1 action 12 |
| `client-runtime/` skeleton | Write script skeletons and `.env.template` | Wave 7 (code only, no runtime test) |
| `sql/cron/pg_cron_canonical.sql` | Write the 10-job definition file | Wave 1 action 3 |
| `infra/docker/` copy | Copy compose files from `greenbrain-v2/deploy/` | Wave 6 action 1 |
| `docs/architecture/db-gap.md` | Document the API/DB gap and resolution options | Wave 6 action 5 |
| Frontend `.env` copy | Copy `.env` and `supabase/` to `apps/frontend/` | Wave 5 action 1 (safe, additive) |
| `apps/frontend/` lock fix | Remove `bun.lock`/`bun.lockb`; run `npm install` | Wave 5 action 2 (no Docker change) |

**Distinction:** All items above are file operations that do not restart any service, do not change any live path, and do not require systemd reload. They can be committed to the monorepo independently.

---

## 8. Commands and checks to prepare before risky waves

Run these checks before starting each indicated wave to confirm baseline health.

### Before Wave 2 (env consolidation)
```bash
# Confirm all 6 timers are active:
systemctl list-timers --all | grep gh-

# Confirm env diff is clean:
grep -E '^[A-Z_]+=' /opt/greenhouse/.env | cut -d= -f1 | sort > /tmp/leg.txt
grep -E '^[A-Z_]+=' /opt/greenbrain-platform/infra/env/dev.env | cut -d= -f1 | sort > /tmp/new.txt
diff /tmp/leg.txt /tmp/new.txt

# Confirm load_env.sh exports variables (not just sets them):
grep "^export" /opt/greenbrain-platform/infra/scripts/load_env.sh | wc -l

# Confirm biweekly/quarterly are not due to run tonight:
systemctl list-timers gh-train-biweekly-all.timer gh-train-quarterly.timer
```

### Before Wave 3 (ML runtime path)
```bash
# Confirm Python files identical between repos:
diff -rq \
  /opt/greenhouse/repo/ \
  /opt/greenbrain-platform/apps/ml-worker/ \
  --exclude="*.bak*" --exclude="parquet_cache" \
  --exclude="models_v4" --exclude="priors_cache" \
  --exclude="*.pyc" --exclude="__pycache__"
# Any differences listed are expected (shell scripts). Pure .py files should show no diff.

# Confirm venv works from monorepo path:
source /opt/greenhouse/venv/bin/activate
cd /opt/greenbrain-platform/apps/ml-worker
python3 -c "from jobs.predict_all import *; print('imports OK')"
python3 -c "from data_access_v1 import DataAccessV1; print('data_access OK')"
deactivate

# Confirm GH_REPO_DIR is not already set to legacy (would mean env change not applied):
source /opt/greenbrain-platform/infra/scripts/load_env.sh && echo $GH_REPO_DIR
```

### Before Wave 4 (storage abstraction)
```bash
# Confirm .bak files exist to apply:
ls /opt/greenbrain-platform/apps/ml-worker/data_access_v1.py.bak_phase2b_fix
ls /opt/greenbrain-platform/apps/ml-worker/jobs/parquet_export/export_features_dense.py.bak_phase2b

# Confirm STORAGE_BACKEND is set in dev.env:
grep STORAGE_BACKEND /opt/greenbrain-platform/infra/env/dev.env

# Confirm get_storage_backend default in storage/backend.py:
grep -A5 "def get_storage_backend" \
  /opt/greenbrain-platform/apps/ml-worker/storage/backend.py

# Capture baseline predict output for one test family before applying changes:
psql "$DATABASE_URL" -c "
  SELECT famiglia_slug, forecast_date, q50
  FROM greenhouse_forecast_results_v2
  WHERE famiglia_slug = (SELECT famiglia_slug FROM famiglie_catalog_static LIMIT 1)
  ORDER BY forecast_date LIMIT 10;"
```

### Before Wave 5 (Docker mount switch)
```bash
# Confirm apps/frontend/.env exists:
test -f /opt/greenbrain-platform/apps/frontend/.env && echo "OK" || echo "MISSING - DO NOT PROCEED"

# Confirm apps/frontend builds without error:
cd /opt/greenbrain-platform/apps/frontend
npm run build 2>&1 | tail -5

# Confirm apps/backend has no import errors:
cd /opt/greenbrain-platform/apps/backend
python3 -c "from app.main import app; print('backend imports OK')"

# Confirm current containers are healthy before touching:
docker ps --format "{{.Names}}: {{.Status}}"
curl -s http://localhost:8002/api/v1/system/health
```

### Before Wave 8 (legacy deprecation)
```bash
# No reference to legacy paths in any live systemd unit:
grep -r "greenhouse/repo\|greenhouse/bin\|greenhouse/.env" /etc/systemd/system/ | grep -v ".bak"

# No reference to old Docker paths in active compose:
grep -r "greenbrain/frontend\|greenbrain-v2/backend" \
  /opt/greenbrain-platform/infra/docker/

# Confirm 7-day clean ML run:
journalctl -u gh-predict-all --since "7 days ago" | grep "ERROR\|greenhouse/repo" | wc -l
# expect 0

# Confirm all pg_cron dangerous jobs still absent:
psql "$DATABASE_URL" -c "SELECT COUNT(*) FROM cron.job WHERE schedule = '* * * * *';"
# expect 0
```

---

## 9. Recommended immediate next action

**Execute Wave 0.**

**Why this is the best next action:**

1. **It removes two active production hazards today** — the every-minute pg_cron jobs and the exposed credential file — with zero code changes and zero downtime risk.
2. **It is fully reversible** — pg_cron jobs can be re-added with a single SQL statement; the credential file deletion is the only irreversible step (which is the point).
3. **It unblocks Wave 1 and Wave 2** by establishing a confirmed baseline health snapshot that all subsequent waves build on.
4. **It reduces Supabase DB load immediately** — jobs 30/38/39 firing every minute consume connection pool during the ETL window. Removing them is a production improvement in itself.
5. **It has no dependency** — no other wave must complete first.

**What to do immediately after Wave 0:**

Write `docs/migration/freeze-baseline.md` and start Wave 1 in parallel. Wave 1 (SQL structure, `.gitignore`, artifact cleanup) involves no runtime changes and can proceed simultaneously with Wave 0's documentation step.

**File to create immediately after:**
`docs/migration/freeze-baseline.md` — containing the `systemctl list-timers`, `docker ps`, and `SELECT * FROM cron.job` snapshots captured at Wave 0 completion. This file is the authoritative record of what the system looked like before migration began.
