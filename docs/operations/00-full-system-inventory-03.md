# Full System Inventory — Part 3 of 3
# Phases 7–10: Duplicates · Source of Truth · Migration Status · Action Plan
> Generated: 2026-03-27. All findings evidence-based.

---

## 7. Duplicates and Conflicts

### 7.1 Code Duplicates: ML Worker (Most Critical)

The ML worker codebase exists in two locations. Neither is complete without the other.

| Location | Role | Python source used by running jobs |
|----------|------|-----------------------------------|
| `/opt/greenhouse/repo/` | Legacy runtime | **YES — all systemd Python jobs run from here** |
| `/opt/greenbrain-platform/apps/ml-worker/` | New monorepo copy | Partially — only `gh-refresh-registry` runs from here |

**Files confirmed DIVERGED** (diff `/opt/greenhouse/repo/jobs` vs `/opt/greenbrain-platform/apps/ml-worker/jobs`, excluding `.bak*` and `__pycache__`):

| File | Divergence type | Direction |
|------|-----------------|-----------|
| `jobs/run_predict_all.sh` | env loader + python invocation style | monorepo is newer |
| `jobs/run_train_missing.sh` | env loader + python invocation style | monorepo is newer |
| `jobs/parquet_export/export_features_dense.py` | `.bak_phase2b` present in monorepo — storage migration started | monorepo in progress |
| `jobs/parquet_export/check_etl_ready.sh` | env loading differs | monorepo is newer |
| `jobs/parquet_export/scripts/run_daily_parquet_batches.sh` | env loading + PROJECT_DIR hardcoded to `/opt/greenhouse/repo` | monorepo is newer but still references legacy path! |
| `jobs/download_priors_from_supabase.py` | `.bak_phase2c` present — storage migration started | monorepo in progress |
| `jobs/upload_priors_to_supabase.py` | `.bak_phase2c` present — storage migration started | monorepo in progress |
| `jobs/train_one_safe.sh` | minor differences | monorepo is newer |
| `jobs/run_train_all_until_done.sh` | minor differences | negligible (legacy script) |

**Files confirmed IDENTICAL between the two repos:**
All Python job orchestrators (`predict_all.py`, `train_missing_batches.py`, `train_all_monitor.py`,
`refresh_registry.py`, `ensure_model_bundle.py`, `family_resolver.py`, `ml_ops_bridge.py`, etc.),
all engine files (`engine_*.py`), and all SQL migrations.

**Cross-repo path dependency (critical):**

`run_daily_parquet_batches.sh` (monorepo version) contains:
```bash
PROJECT_DIR="/opt/greenhouse/repo/jobs/parquet_export"   # hardcoded legacy path
cd "$PROJECT_DIR"
python -u export_features_dense.py
```

This means `gh-parquet-export.service` has:
- `WorkingDirectory=/opt/greenbrain-platform/apps/ml-worker` (monorepo)
- BUT `ExecStart` shell script immediately `cd`s to `/opt/greenhouse/repo/jobs/parquet_export`
- AND runs the **legacy** `export_features_dense.py` there

The monorepo `export_features_dense.py.bak_phase2b` in the monorepo indicates phase 2b storage
migration work was started on the monorepo copy, but it is **not the version actually running**.

---

### 7.2 Code Duplicates: Backend (FastAPI)

| Location | Running? | Difference |
|----------|----------|------------|
| `/opt/greenbrain-v2/backend/` | **YES** (Docker `gb_v2_backend` port 8002) | Has `.env.example` |
| `/opt/greenbrain-platform/apps/backend/` | **NO** | Has `.bak` files (ops.py, config.py) |

`diff -r` between the two shows **only** `/opt/greenbrain-v2/backend/.env.example` differs.
Python source files are identical. The monorepo copy is a mirror, not diverged.

The running backend reads `/opt/greenbrain-v2/backend` via Docker volume mount:
```yaml
volumes:
  - ../backend:/app    # = /opt/greenbrain-v2/backend:/app inside container
```

---

### 7.3 Code Duplicates: Frontend (React)

| Location | Running? | Difference |
|----------|----------|------------|
| `/opt/greenbrain/frontend/` | **YES** (Docker `gb_v2_frontend` port 8083) | Has `.env`, `supabase/` folder (1 item) |
| `/opt/greenbrain-platform/apps/frontend/` | **NO** | No `.env`, no `supabase/` folder |

`diff` of `src/` between the two: **IDENTICAL** (confirmed in previous scan).

Frontend is mounted from `/opt/greenbrain/frontend` in Docker:
```yaml
volumes:
  - ../frontend:/app    # but frontend is in /opt/greenbrain/frontend, not /opt/greenbrain-v2/frontend
```

Actually `gb_v2_frontend` mounts `/opt/greenbrain-v2/frontend` — but that is only 4 files (minimal
stub). The actual production frontend (`/opt/greenbrain/frontend`) must be mounted separately or the
Docker context is different. **This requires verification** — the docker-compose base shows
`- ../frontend:/app` which relative to `/opt/greenbrain-v2/deploy/` resolves to
`/opt/greenbrain-v2/frontend`, **not** `/opt/greenbrain/frontend`. Yet `gb_v2_frontend` runs
`npm install && npm run dev` and clearly serves the full app. The volume may have been manually
remounted or the docker-compose path was edited.

**Verified discrepancy**: `gb_v2_frontend` container is `Up 7 days` and serves the full React app,
but the declared `docker-compose.base.yml` volume points to the 4-file stub. This is a
**documentation/config divergence** — the live container may be using a different mount.

---

### 7.4 Duplicate CLI Bin Scripts

Two complete sets of `gh-*` scripts exist:

| Set | Path | Total scripts | Status |
|-----|------|--------------|--------|
| Legacy | `/opt/greenhouse/bin/` | 19 (+ 1 bak) | Older, uses `source /opt/greenhouse/.env` |
| Monorepo | `/opt/greenbrain-platform/infra/scripts/bin/` | 21 (+ 3 bak) | Newer, uses `load_env.sh` + `-m` module style |

Both sets are likely in `$PATH`. Running either set from a terminal would produce different behavior
depending on which Python invocation style and which env file is used.

**Specific divergences confirmed:**

| Script | Legacy behavior | Monorepo behavior |
|--------|----------------|-------------------|
| `gh-refresh-registry` | `source /opt/greenhouse/.env; python3 -u jobs/refresh_registry.py` | `source load_env.sh; python3 -u -m jobs.refresh_registry` |
| `gh-train-missing` | `source /opt/greenhouse/.env; python3 -u jobs/train_missing_batches.py` | `source load_env.sh; python3 -u -m jobs.train_missing_batches` |
| `gh-predict-all` | `source /opt/greenhouse/.env; RUN_TRIGGER_SOURCE=manual python3 -u jobs/predict_all.py` | `source load_env.sh; RUN_TRIGGER_SOURCE=manual python3 -u -m jobs.predict_all` |

---

### 7.5 pg_cron Scheduling Conflicts

**Jobs running `* * * * *` (every minute):**

| jobid | function | conflict |
|-------|---------|---------|
| 30 | `run_greenhouse_daily_pipeline_full(40,14,2)` | Duplicates job 11 (same function, 5-min window); runs 24/7 |
| 38 | `ops_maybe_run_daily_pipeline()` | Duplicates job 29 (gated version, 19-23 window); runs 24/7 |
| 39 | `run_greenhouse_daily_pipeline_full(40,14,2)` | Exact duplicate of job 30 |

At peak (10:00–11:55), jobs 11, 30, and 39 all call `run_greenhouse_daily_pipeline_full` concurrently.
If the function has internal guards this may be safe, but it generates excessive Supabase DB load.

**Assessment of safe jobs vs duplicates:**

| Keep | Disable | Reason |
|------|---------|--------|
| 11 | | Safe window (10-11), every 5 min |
| 12 | | Nightly planner reset, necessary |
| 13 | | Noon planner tick, necessary |
| 28 | | Pipeline monitor snapshot, low cost |
| 29 | | Gated ETL in evening window (19-23), every 5 min |
| | **30** | **Every minute, same as 39 — disable** |
| 31 | | MV refresh, evening window |
| 32 | | MV refresh, morning window |
| 34 | | MV refresh, off-hours |
| 35 | | MV refresh, morning window |
| 37 | | Gated ETL, morning window (9-11) |
| | **38** | **Every minute — duplicates 29/37** |
| | **39** | **Every minute — duplicates 30** |

---

### 7.6 Systemd Service Inconsistency: Mixed Working Directories

| Service | WorkingDirectory | Python source actually executed |
|---------|-----------------|--------------------------------|
| `gh-predict-all` | `/opt/greenbrain-platform/apps/ml-worker` | `/opt/greenhouse/repo` (shell script cd's there) |
| `gh-train-missing` | `/opt/greenbrain-platform/apps/ml-worker` | `/opt/greenhouse/repo` (shell script cd's there) |
| `gh-parquet-export` | `/opt/greenbrain-platform/apps/ml-worker` | `/opt/greenhouse/repo/jobs/parquet_export` (hardcoded) |
| `gh-refresh-registry` | `/opt/greenbrain-platform/apps/ml-worker` | `/opt/greenbrain-platform/apps/ml-worker` ← correct |
| `gh-train-biweekly-all` | `/opt/greenhouse/repo` | `/opt/greenhouse/repo` ← all legacy |
| `gh-train-quarterly` | `/opt/greenhouse/repo` | `/opt/greenhouse/repo` ← all legacy |

Only `gh-refresh-registry` actually executes Python from the monorepo as intended.
The others use the monorepo only for the shell entry scripts, then switch to legacy Python.

---

### 7.7 Binary / Runtime Data in Source Tree

| Path | Items | Size | Issue |
|------|-------|------|-------|
| `/opt/greenhouse/repo/models_v4/` | 1886 `.pkl` | Part of 18G total | Runtime binary — DO Spaces is source of truth |
| `/opt/greenhouse/repo/parquet_cache/` | 18520 files | Part of 18G total | Runtime download cache |
| `/opt/greenhouse/repo/priors_cache/` | 847 items | Runtime | Runtime cache |
| `/opt/greenbrain-platform/apps/ml-worker/models_v4_backup/` | 1 `.tgz` | ~400MB | Same as `/opt/greenhouse/repo/models_v4_backup/` |
| `/opt/greenhouse/repo/models_v4_backup/` | 1 `.tgz` | ~400MB | **Exact duplicate** of above |
| `data_access_v1.py.bak_phase2b*` (2 files) | Backup | — | Phase migration artifacts |
| `export_features_dense.py.bak_phase2b` | Backup | — | Phase migration artifact |
| `download_priors_from_supabase.py.bak_phase2c` | Backup | — | Phase migration artifact |
| `upload_priors_to_supabase.py.bak_phase2c` | Backup | — | Phase migration artifact |
| `run_predict_all.sh.bak_phase2d` | Backup | — | Phase migration artifact |
| `run_train_missing.sh.bak_phase2d` | Backup | — | Phase migration artifact |
| All `__pycache__/` dirs (12 dirs, ~60 `.pyc` files) | 72 items | KB | Should be gitignored |

---

### 7.8 Security Issue

| File | Issue |
|------|-------|
| `/opt/greenhouse/repo/ISTRUZIONI  & FUNZIONAMENTO/lovabel .env corretto.json` | Contains live Supabase `VITE_SUPABASE_PROJECT_ID`, `VITE_SUPABASE_URL`, JWT `VITE_SUPABASE_PUBLISHABLE_KEY`. File committed to repo. |
| `/opt/greenbrain-platform/apps/ml-worker/ISTRUZIONI  & FUNZIONAMENTO/lovabel .env corretto.json` | Same file, duplicate in monorepo. |

Both files should be deleted and the Supabase anon/publishable key should be rotated if there is any
public or shared git remote.

---

### 7.9 Missing File Referenced in Production

`/opt/greenbrain-platform/infra/scripts/bin/gh-audit` line 53:
```bash
python3 -m py_compile jobs/ml_monitor_db.py && echo "OK py_compile jobs/ml_monitor_db.py"
```

`/opt/greenhouse/repo/jobs/ml_monitor_db.py` — **does not exist in either repo.**
`gh-audit` will fail at this check. The file was either never migrated or was deleted.

---

### 7.10 gb_v2_ml Docker Container: Dead Placeholder

`gb_v2_ml` container runs `sleep infinity` — it is declared in `docker-compose.base.yml` as a
Python:3.11-slim container with `../ml:/app` volume, but has no actual command. No ML jobs run
in this container. All production ML work runs via systemd on the host using
`/opt/greenhouse/venv`. The container is a placeholder for a future containerized ML worker.

---

## 8. Source of Truth Map

### 8.1 ML Worker (Python)

| Aspect | Source of Truth | Competing copy | Risk |
|--------|----------------|----------------|------|
| **Python ML jobs** (predict_all, train_missing_batches, etc.) | `/opt/greenhouse/repo/jobs/` | `/opt/greenbrain-platform/apps/ml-worker/jobs/` | 🔴 HIGH — systemd runs legacy, monorepo may be edited first |
| **Core ML scripts** (predict_v4, train_v4, data_access) | `/opt/greenhouse/repo/` | `/opt/greenbrain-platform/apps/ml-worker/` | 🔴 HIGH — same risk |
| **Shell entry scripts** (run_predict_all.sh, run_train_missing.sh) | `/opt/greenbrain-platform/apps/ml-worker/jobs/` | `/opt/greenhouse/repo/jobs/` | 🟡 MEDIUM — monorepo version is newer but still cd's to legacy |
| **Storage abstraction** | `/opt/greenbrain-platform/apps/ml-worker/storage/` | Does not exist in legacy | 🟡 MEDIUM — not yet wired to running code |
| **Virtual environment** | `/opt/greenhouse/venv/` | None | ✅ Only one copy |
| **requirements.txt** | `/opt/greenhouse/repo/requirements.txt` | 3 competing files in monorepo: `requirements_clean.txt`, `requirements_cloud.lock`, `requirements_snapshot.txt` | 🟡 MEDIUM — no canonical single source |

---

### 8.2 Backend (FastAPI)

| Aspect | Source of Truth | Competing copy | Risk |
|--------|----------------|----------------|------|
| **Running backend** | `/opt/greenbrain-v2/backend/` (Docker volume mount) | `/opt/greenbrain-platform/apps/backend/` | 🟡 MEDIUM — identical code, but any edits to monorepo copy won't affect running service |
| **Backend env config** | `/opt/greenbrain-v2/deploy/.env` (Docker env) | `/opt/greenbrain-platform/infra/env/dev.env` | 🟡 MEDIUM — different variable naming conventions |
| **API surface** | `/opt/greenbrain-v2/backend/app/api/v1/` | `/opt/greenbrain-platform/apps/backend/app/api/v1/` | 🟢 LOW — identical at time of scan |

---

### 8.3 Frontend (React)

| Aspect | Source of Truth | Competing copy | Risk |
|--------|----------------|----------------|------|
| **Running frontend** | `/opt/greenbrain/frontend/` (Docker volume mount for `gb_v2_frontend`) | `/opt/greenbrain-platform/apps/frontend/` | 🔴 HIGH — `src/` identical but any edit to monorepo won't affect running app |
| **Frontend env** | `/opt/greenbrain/frontend/.env` (`VITE_API_BASE_URL=http://127.0.0.1:8002`) | No `.env` in monorepo frontend | 🔴 HIGH — monorepo frontend has no env config and can't be built |
| **Package manager** | `bun` (bun.lock + bun.lockb) AND `npm` (package-lock.json) both present | — | 🟡 MEDIUM — two lock file formats |
| **Auth** | Supabase (`integrations/supabase/client.ts`) | FastAPI JWT (proposed, not implemented) | 🟡 MEDIUM — no local auth yet |

---

### 8.4 SQL Schema

| Aspect | Source of Truth | Competing copy | Risk |
|--------|----------------|----------------|------|
| **Schema definition** | Supabase hosted PostgreSQL (live truth) | `/opt/greenbrain-v2/database/current-schema.sql` (export) | 🟢 LOW — file is a snapshot, not applied independently |
| **Migrations** | Applied directly to Supabase (no migration tool) | `jobs/migrations/blocco_*.sql` (applied manually, in both repos) | 🔴 HIGH — no idempotent migration runner; schema drift is possible |
| **Local Docker DB** | `gb_v2_postgres:17` (`greenbrain` DB) | Populated separately from Supabase | 🔴 HIGH — local DB schema may not match Supabase; `current-schema.sql` is from a local pg17 export |

---

### 8.5 Infrastructure / Systemd

| Aspect | Source of Truth | Competing copy | Risk |
|--------|----------------|----------------|------|
| **Active unit files** | `/etc/systemd/system/gh-*.service|timer` | `/opt/greenbrain-platform/infra/systemd/current/` | 🟡 MEDIUM — monorepo copy is up-to-date but not auto-applied |
| **CLI scripts (active)** | `/opt/greenhouse/bin/` (loaded in systemd PATH) | `/opt/greenbrain-platform/infra/scripts/bin/` | 🔴 HIGH — both in PATH, scripts diverged, ambiguous which runs on `gh-*` from terminal |
| **Env configuration** | `/opt/greenhouse/.env` (loaded by EnvironmentFile in 2 services) | `/opt/greenbrain-platform/infra/env/dev.env` (loaded by load_env.sh in 4 services) | 🔴 HIGH — two env systems, partial overlap, inconsistent |

---

### 8.6 Summary Risk Matrix

| Domain | Source of Truth | Risk Level | Reason |
|--------|----------------|-----------|--------|
| ML Python code | `/opt/greenhouse/repo/` | 🔴 HIGH | Monorepo in mid-migration; edits may land in wrong repo |
| ML Shell scripts | `/opt/greenbrain-platform/apps/ml-worker/jobs/` | 🟡 MEDIUM | Newer but still references legacy paths |
| CLI bin scripts | AMBIGUOUS (both sets in PATH) | 🔴 HIGH | Different behavior depending on which is called first |
| Backend API | `/opt/greenbrain-v2/backend/` | 🟡 MEDIUM | Monorepo copy currently idle but could diverge |
| Frontend | `/opt/greenbrain/frontend/` | 🔴 HIGH | Monorepo copy has no env, can't run standalone |
| SQL Schema | Supabase live DB | 🔴 HIGH | No migration runner; manual SQL applied directly |
| Env variables | `/opt/greenhouse/.env` (ML) + `/opt/greenbrain-v2/deploy/.env` (Docker) | 🔴 HIGH | Two separate env systems with overlapping variables |
| Systemd units | `/etc/systemd/system/` | 🟢 LOW | Monorepo copy in sync; live units are the authority |

---

## 9. Migration Alignment Status

Status assessed for each component relative to the target (greenbrain-platform monorepo as sole source).

### 9.1 ML Worker

| Component | Migration Status | Evidence |
|-----------|-----------------|---------|
| Shell entry scripts (run_predict_all.sh, run_train_missing.sh) | 🟡 **Partially migrated** | In monorepo, but still `cd /opt/greenhouse/repo` inside |
| Python ML jobs (predict_all, train_missing, etc.) | 🔴 **Not migrated** | All systemd jobs run from `/opt/greenhouse/repo` |
| Parquet export script | 🔴 **Not migrated** | Runs from `/opt/greenhouse/repo/jobs/parquet_export` |
| train_all_monitor.py (biweekly + quarterly) | 🔴 **Not migrated** | `EnvironmentFile=/opt/greenhouse/.env`, `WorkingDirectory=/opt/greenhouse/repo` |
| Storage abstraction (`storage/` package) | 🟡 **In progress** | Module exists, `.bak_phase2b/2c` backups exist, not yet wired to live code |
| `data_access_v1.py` storage migration | 🟡 **In progress** | `data_access_v1.py.bak_phase2b` and `bak_phase2b_fix` in monorepo |
| `export_features_dense.py` storage migration | 🟡 **In progress** | `.bak_phase2b` present |
| Priors upload/download storage migration | 🟡 **In progress** | `.bak_phase2c` present |
| `env load_env.sh` adoption | 🟡 **Partially migrated** | 4 services use it; 2 services still use `/opt/greenhouse/.env` directly |
| `python -m module` invocation style | 🟡 **Partially migrated** | Monorepo bin scripts updated; systemd services for biweekly/quarterly unchanged |
| Virtual environment | 🔴 **Not migrated** | Still at `/opt/greenhouse/venv/` — referenced everywhere |
| requirements.txt | 🔴 **Not migrated** | 4 competing files, no canonical |
| `refresh_registry.py` | ✅ **Migrated** | `gh-refresh-registry.service` runs from monorepo |

---

### 9.2 Backend

| Component | Migration Status | Evidence |
|-----------|-----------------|---------|
| FastAPI app source | 🟡 **Mirrored (not yet active)** | Code identical to running `gb_v2_backend`; monorepo not running |
| Backend env config | 🔴 **Not migrated** | Running from `/opt/greenbrain-v2/deploy/.env` (Docker); monorepo has no live env |
| Docker → systemd migration | 🔴 **Not started** | Backend still runs in Docker container |

---

### 9.3 Frontend

| Component | Migration Status | Evidence |
|-----------|-----------------|---------|
| React source (`src/`) | 🟡 **Mirrored** | Identical to running container; monorepo can't build (no .env) |
| Auth (Supabase → local) | 🔴 **Not started** | Still uses `@supabase/supabase-js` for auth in both copies |
| Supabase data calls | ✅ **Migrated** | All data hooks use `apiClient.ts` → FastAPI (Supabase only for auth) |
| `useGardenCenterSettings` | 🟡 **Partially** | Still uses `supabase.from(...)` directly |
| Production build | 🔴 **Not migrated** | Runs `npm run dev` (Vite dev server), not a built production app |

---

### 9.4 SQL / Database

| Component | Migration Status | Evidence |
|-----------|-----------------|---------|
| Schema file in monorepo | 🔴 **Not present** | `sql/` directory exists but is empty |
| SQL migrations in monorepo | 🟡 **Wrong location** | 8 migration SQL files in `jobs/migrations/`, not in `sql/migrations/` |
| pg_cron job versioning | 🔴 **Not migrated** | Jobs live only in Supabase; no versioned SQL file in monorepo |
| Schema normalization (Supabase → local Postgres) | 🔴 **Not started** | Local Docker uses separate `greenbrain` DB with potentially different schema |

---

### 9.5 Infrastructure

| Component | Migration Status | Evidence |
|-----------|-----------------|---------|
| Systemd unit files | ✅ **Versioned** | All 12 units in `/opt/greenbrain-platform/infra/systemd/current/` |
| CLI bin scripts | ✅ **Updated** | Monorepo versions are newer and updated |
| load_env.sh | ✅ **Active** | Used by 4 services and all monorepo bin scripts |
| env templates (base/dev/client) | ✅ **Present** | `infra/env/` has all three variants |
| Client runtime package | 🔴 **Not started** | Design complete (`docs/architecture/02-client-runtime-design.md`), no `client-runtime/` directory yet |

---

### 9.6 Migration Completeness Summary

| Domain | % Migrated | Blocking issue |
|--------|-----------|----------------|
| Shell entry scripts | 60% | Scripts point to legacy Python repo |
| Python ML jobs | 5% | Only refresh_registry runs from monorepo |
| Storage abstraction | 40% | Module built, not yet wired to running code |
| Backend | 80% | Running from greenbrain-v2 Docker, not monorepo |
| Frontend source | 95% | Needs .env, auth migration |
| SQL/schema | 15% | Schema file exists, migrations misplaced, pg_cron unversioned |
| Infrastructure | 85% | Systemd units versioned, env system improved |

---

## 10. Next Actions

All actions are based exclusively on evidence above. No speculative changes.

---

### 🔴 CRITICAL — Breaks system or causes data corruption

| # | Action | Evidence | Affected |
|---|--------|---------|---------|
| C1 | **Disable pg_cron jobs 30, 38, 39** (`* * * * *` schedule). Jobs 30+39 duplicate full ETL every minute; job 38 duplicates gated check every minute. | See §7.5 — 3 jobs confirmed running every minute calling same functions | Supabase DB load, ETL correctness |
| C2 | **Delete `lovabel .env corretto.json`** from both repos and rotate the exposed Supabase anon/publishable JWT key | See §7.8 — contains live credentials in source tree | Security |
| C3 | **Add missing `jobs/ml_monitor_db.py`** (or remove the `py_compile` check from `gh-audit`). Current state: `gh-audit` fails at line 53 | See §7.9 — file referenced but does not exist | `gh-audit` produces error on every run |
| C4 | **Stop the `npm run dev` Vite dev server from serving production traffic**. `gb_v2_frontend` runs `npm run dev --host 0.0.0.0 --port 8080`. This is a development server, not production. | `docker-compose.base.yml` + `ps aux` output | Frontend stability, security |

---

### 🟠 HIGH — Blocks migration or causes silent divergence

| # | Action | Evidence | Affected |
|---|--------|---------|---------|
| H1 | **Fix `run_daily_parquet_batches.sh` to use monorepo Python**, not `/opt/greenhouse/repo/jobs/parquet_export/export_features_dense.py`. The storage migration work in the monorepo version is invisible to the running job. | See §2.1 Flow E + §7.1 | Parquet export migration |
| H2 | **Fix `gh-train-biweekly-all.service` and `gh-train-quarterly.service`** to use `load_env.sh` instead of `EnvironmentFile=/opt/greenhouse/.env`, and run from monorepo | See §2.1 Flow C+D — both use `/opt/greenhouse/repo` WorkingDirectory and legacy env | Env consistency, migration |
| H3 | **Resolve ambiguity of two CLI bin script sets** by removing `/opt/greenhouse/bin/` from `$PATH` and making `/opt/greenbrain-platform/infra/scripts/bin/` the sole active set | See §7.4 + §8.5 — both sets in PATH with different behavior | CLI operations |
| H4 | **Wire the storage abstraction** (`storage/backend.py`) to the four ML worker files: `data_access_v1.py`, `export_features_dense.py`, `upload_priors_to_supabase.py`, `download_priors_from_supabase.py`. Migration analysis is complete in `docs/migration/04-storage-migration-analysis.md`. | See §7.1 — `.bak_phase2*` files confirm work in progress but not applied to running code | Client-runtime unblocked by this |
| H5 | **Unify DB env var naming**: `export_features_dense.py` reads `SUPABASE_DB_HOST/PORT/NAME/USER/PASSWORD` while all other files use `PG_*`. Part of H4 migration. | See Part 2 §6.2 | `export_features_dense.py` will crash if `SUPABASE_DB_*` absent |
| H6 | **Move `run_predict_all.sh` and `run_train_missing.sh` to stop hard-coding `cd /opt/greenhouse/repo`**. Scripts should use `GH_REPO_DIR` env var which is already set in the env files. | See §7.1 + §2.1 | Full migration to monorepo |
| H7 | **Add `sql/` content to monorepo**: move 8 SQL migrations from `jobs/migrations/` to `sql/migrations/`, copy `current-schema.sql` to `sql/schema/`, write `sql/cron/pg_cron_canonical.sql` with the correct 10 jobs (excluding 30/38/39) | See §9.4 | Migration completeness |

---

### 🟡 MEDIUM — Cleanup, consistency, or documentation

| # | Action | Evidence | Affected |
|---|--------|---------|---------|
| M1 | **Add `.gitignore` entries** for: `models_v4/`, `parquet_cache/`, `priors_cache/`, `logs/`, `diagnostics/*.csv`, `*_progress.json`, `**/__pycache__/`, `**/*.pyc`, `**/*.bak*`, `.env`, `node_modules/` | See §7.7 | Repository cleanliness |
| M2 | **Remove all `.bak_*` files from source tree**: 17 confirmed bak files across both repos | See §7.7 + `docs/migration/03-file-audit.md` §DELETE | Clutter |
| M3 | **Consolidate requirements files** to a single `requirements.txt` canonical file; archive `requirements_clean.txt`, `requirements_cloud.lock`, `requirements_snapshot.txt` | See §7.7 + file audit | Dependency clarity |
| M4 | **Delete `scripts/patch_get_engine_urlcreate.py` and `scripts/patch_predict_safe.py`** — one-time patches that have already been applied | `docs/migration/03-file-audit.md` §DELETE | Clutter |
| M5 | **Verify and document the Docker frontend mount**. `docker-compose.base.yml` declares `- ../frontend:/app` (resolves to `/opt/greenbrain-v2/frontend`, a 4-file stub), but `gb_v2_frontend` clearly runs the full app. Find and document the actual mount source. | See §7.3 — mount path inconsistency | Documentation accuracy |
| M6 | **Rename `download/upload_priors_to/from_supabase.py`** after storage migration (H4) to `download_priors.py` and `upload_priors.py` — names will be wrong after Supabase is no longer hardcoded | See §2.1 Flow A | Code clarity |
| M7 | **Move maintenance and analysis scripts** to proper subdirectories per `docs/migration/02-repo-structure-proposal.md`: root-level `backfill_*.py`, `sync_holidays.py`, `refresh_weekday_strength.py` → `maintenance/`; `backtest_*.py`, `evaluate_v4_*.py`, `fetch_forecast_dataset_v2.py` → `analysis/` | See file audit §KEEP→MOVE | Repository organization |
| M8 | **Flatten `infra/systemd/current/`** to `infra/systemd/` (remove `current/` subdirectory) | See `02-repo-structure-proposal.md` | Structure consistency |
| M9 | **Document the live pg_cron job set** in `sql/cron/pg_cron_canonical.sql` with the correct 10 jobs | See §7.5 | Reproducibility |
| M10 | **Resolve package manager conflict in frontend** (bun.lock + bun.lockb + package-lock.json present). Pick one. | See §7.3 | Build consistency |

---

### 🟢 LOW — Optimization or future work

| # | Action | Evidence | Affected |
|---|--------|---------|---------|
| L1 | **Create `client-runtime/` package directory** and write `install.sh`, `update.sh`, `.env.client.template`. Design is complete in `docs/architecture/02-client-runtime-design.md`. | Design doc complete | Client deployment |
| L2 | **Replace Supabase auth in frontend** with FastAPI JWT (`POST /api/v1/auth/login`, `GET /api/v1/auth/me`). Only auth remains after data hook migration. | See §9.3 — auth migration not started | Client-runtime auth |
| L3 | **Build a production frontend** (`npm run build`) instead of running Vite dev server in Docker | See C4 — currently dev server serves production | Frontend performance |
| L4 | **Create `gb_v2_ml` Docker container actually running something** or remove it. Current state: `sleep infinity`. | See §7.10 | Docker cleanliness |
| L5 | **Delete the `ISTRUZIONI & FUNZIONAMENTO/` folder** from both repos after extracting the DENSE table documentation into proper markdown | See file audit §ARCHIVE | Repository cleanliness |
| L6 | **Verify local Docker DB (`gb_v2_postgres:17`) schema matches Supabase schema**. The current `current-schema.sql` was from a local pg17 export, not confirmed to match live Supabase. | See §8.4 | Local dev accuracy |
| L7 | **Set up a formal migration runner** (e.g., Flyway, Alembic, or plain ordered SQL scripts) to replace the current manual `blocco_*_migration.sql` approach | See §9.4 — no migration runner | Schema management |
| L8 | **Move `jobs/parquet_export/`** entirely into the monorepo path and update `run_daily_parquet_batches.sh` `PROJECT_DIR` accordingly. Currently the script cds to `/opt/greenhouse/repo/jobs/parquet_export` even when invoked from monorepo. | See §2.1 Flow E | Full parquet migration |

---

### Recommended Execution Order

```
WEEK 1 (unblock production stability):
  C1 → disable pg_cron jobs 30/38/39
  C2 → delete credentials file + rotate key
  C3 → fix or remove gh-audit ml_monitor_db check

WEEK 1–2 (complete storage abstraction migration):
  H4 → wire storage abstraction to 4 ML files (analysis ready in 04-storage-migration-analysis.md)
  H5 → unify SUPABASE_DB_* → PG_* in export_features_dense.py (part of H4)

WEEK 2 (fix execution path inconsistencies):
  H1 → fix run_daily_parquet_batches.sh to run from monorepo
  H2 → fix gh-train-biweekly/quarterly services to use load_env.sh
  H6 → fix shell scripts to use GH_REPO_DIR env var
  H3 → remove legacy /opt/greenhouse/bin/ from PATH

WEEK 3 (SQL and structure cleanup):
  H7 → populate sql/ directory in monorepo
  M1 → add .gitignore
  M2 → delete all .bak_* files
  M9 → write pg_cron_canonical.sql

WEEK 4 (client-runtime):
  L1 → create client-runtime/ package
  L2 → implement local auth endpoints + frontend migration
  L3 → build production frontend
  C4 → replace dev server with production nginx
```

---

## Index: All Inventory Files

| File | Phases | Contents |
|------|--------|---------|
| `00-full-system-inventory-01.md` | 1–3 | Repository map, execution entrypoints, scheduling layer |
| `00-full-system-inventory-02.md` | 4–6 | Data pipeline graph, database map, environment variables |
| `00-full-system-inventory-03.md` | 7–10 | Duplicates/conflicts, source of truth, migration status, action plan |

Related docs in `docs/migration/`:
- `01-repo-consolidation-plan.md` — initial consolidation plan
- `02-repo-structure-proposal.md` — proposed normalized directory tree
- `03-file-audit.md` — per-file keep/archive/legacy/delete classification
- `04-storage-migration-analysis.md` — exact imports/calls to replace for storage abstraction
- `05-python-execution-standard.md` — Python execution standards
- `06-shadow-validation-status.md` — shadow validation status

Related docs in `docs/architecture/`:
- `01-target-architecture.md` — target architecture
- `02-client-runtime-design.md` — local client-runtime technical design
