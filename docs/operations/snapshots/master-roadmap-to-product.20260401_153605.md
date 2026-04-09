# GreenBrain — Master Roadmap to Product
> Execution plan to transform the current hybrid system into one canonical dev-cloud
> platform and one installable client-local runtime, sharing a single codebase.
> Updated: 2026-04-01.
> Evidence sources: `docs/migration/source-of-truth.md` · `docs/migration/migration-map.md` ·
> `docs/architecture/dev-cloud-vs-client-local.md` · `docs/architecture/runtime-current-state.md` ·
> `docs/operations/00-full-system-inventory-0{1,2,3}.md`

---

## 1. Final Target

Two modes. One codebase. Zero duplication.

### Dev-cloud
- All source in `greenbrain-platform/` monorepo — no active external paths
- FastAPI backend + React frontend run as production Docker images built from monorepo
- ML pipeline runs from `apps/ml-worker/` via systemd on the cloud host
- PostgreSQL on local Docker (`gb_v2_postgres`) populated by ETL + ML via pg_cron
- Schema versioned in `sql/`; migrations applied via `sql/migrate.sh`
- Auth via FastAPI JWT (no Supabase JS dependency)
- Single env system (`infra/env/base.env + dev.env` via `load_env.sh`)
- pg_cron canonical jobs defined in `sql/cron/` and versioned

### Client-local
- Installed via `client-runtime/install.sh` on customer's Linux server
- No Supabase account, no DigitalOcean account, no internet required at runtime
- Same FastAPI backend and React frontend Docker images as dev-cloud
- Same PostgreSQL 17 schema, loaded from `client-runtime/sql/init/` wave sequence
- ML pipeline runs from `apps/ml-worker/` with `STORAGE_BACKEND=local`
- ETL runs via pg_cron extension in local Docker PostgreSQL
- Auth via same FastAPI JWT
- Updated via `client-runtime/update.sh` (new schema waves + model refresh)

### What never changes between modes
The entire application layer: all FastAPI routes, all React components, all SQL
objects (tables, views, functions), all ML algorithms and training logic.
The mode is a configuration choice, not a product fork.

---

## 2. Current State

**What is running today:**

| Layer | Running from | Mode | State |
|-------|-------------|------|-------|
| FastAPI backend | `/opt/greenbrain-v2/backend/` | Docker `gb_v2_backend :8002` | Real, legacy path |
| React frontend | `/opt/greenbrain/frontend/` | Docker `gb_v2_frontend :8083` Vite dev server | Real, legacy path, dev server |
| PostgreSQL | Docker `gb_v2_postgres :5433` | Local snapshot schema, not ETL-populated | Real, schema drift unknown |
| ML training | `/opt/greenhouse/repo/` | systemd `gh-train-biweekly/quarterly` | Real, legacy path |
| ML prediction | `/opt/greenhouse/repo/` | systemd `gh-predict-all` | Real, legacy path |
| ETL | Supabase pg_cron (13 jobs, 3 rogue) | Supabase cloud PostgreSQL | Real, 3 jobs are every-minute duplicates |
| Planner scheduler | Supabase pg_cron `nightly_roll4_tick` | Supabase cloud PostgreSQL | Real |
| Storage (parquet) | Supabase Storage `ml-snapshots` | Hardcoded SDK calls | Real, abstraction written but not wired |
| Storage (models) | DO Spaces `greenbrainmodels` | Hardcoded boto3 calls | Real, abstraction written but not wired |
| Auth | Supabase JS `integrations/supabase/client.ts` | Browser, Supabase cloud | Real, cloud-only |

**Client-local state today:**
- `client-runtime/sql/init/` — 12 init waves applied (Wave 7A + 7B.1 + 7B.2A-J)
- ~38/58 API endpoints return HTTP 200 in client-runtime
- 5 analytics endpoints REAL/BUSINESS-VALIDATED in dev-cloud:
  `series-breakdown`, `future-windows-stats`, `compare-series`, `entity-summary`, `reorder-suggestions`
- Client-runtime data is always empty (ETL not portable yet)
- No auth, no frontend image, no install script

---

## 3. What Is Already Solid

These are done or require only mechanical completion (no design uncertainty):

1. **FastAPI backend portability** — zero Supabase SDK usage; all DB calls via `POSTGRES_*`
   env vars + SQLAlchemy. Same binary runs in both modes.
2. **Frontend data hooks** — all `src/hooks/` and API calls use `apiClient.ts` → FastAPI.
   Only auth remains on Supabase.
3. **Storage abstraction module** — `apps/ml-worker/storage/` factory complete
   (`LocalStorageBackend`, `S3StorageBackend`, `SupabaseStorageBackend`). Design correct.
   `.bak_phase2b/2c` contain the correct migration of all 4 calling files.
4. **Schema wave approach** — 12 init files applied; idempotent; wave sequence works.
   Wave 7B.1 (27 endpoints), Wave 7B.2A-J (partial Tier 3/4) validated.
5. **Analytics endpoint contract** — 5 endpoints REAL/BUSINESS-VALIDATED in dev-cloud.
   SQL objects (tables + views) already in client-runtime as stubs.
6. **Cloud dependency map** — all 8 Supabase/DO dependencies documented with exact
   replacement decisions in `02-client-runtime-design.md`.
7. **`load_env.sh` mechanism** — works for 4 of 6 systemd services. Pattern proven.
8. **`gh-refresh-registry` from monorepo** — one ML service already runs from monorepo.
   Proves the migration pattern works for all others.
9. **`/ops/health` tolerant behavior** — returns `degraded`, not 500, on missing schema.
10. **`/planner/calendar-events` tolerant behavior** — 200 empty without schema.
11. **Security issues identified** — credential files located, rotation plan clear.
12. **pg_cron rogue jobs identified** — #30/38/39 confirmed duplicate; unschedule is reversible.

---

## 4. What Is Still Hybrid

These are unresolved splits where live execution and target SoT are different paths.

| Split | Live from | Target | Impact if left as-is |
|-------|-----------|--------|---------------------|
| Backend source | `/opt/greenbrain-v2/backend/` | `apps/backend/` | Next code change creates divergence |
| Frontend source | `/opt/greenbrain/frontend/` | `apps/frontend/` | Next code change creates divergence |
| ML Python (5/6 jobs) | `/opt/greenhouse/repo/` | `apps/ml-worker/` | Storage abstraction has zero production effect |
| ML shell scripts | Monorepo path but redirect to legacy | Monorepo, no redirect | Shell scripts are wiring to the wrong Python |
| ML env (biweekly/quarterly) | `/opt/greenhouse/.env` | `infra/env/dev.env` via `load_env.sh` | These 2 services bypass monorepo env entirely |
| CLI bin scripts | Both in PATH (ambiguous) | `infra/scripts/bin/` only | `gh-predict-all` from terminal behaves differently than from timer |
| Docker compose | `/opt/greenbrain-v2/deploy/` | `infra/docker/` | Volume mounts reference non-monorepo paths |
| Schema | Supabase cloud (live) + local Docker snapshot (API) | Single versioned source | Drift between Supabase and local DB is undetected |
| Auth | Supabase JS | FastAPI JWT | client-local login impossible |
| Storage calls | Direct Supabase SDK + boto3 in ML code | Storage factory (`STORAGE_BACKEND` env var) | `STORAGE_BACKEND=local` has no effect |
| pg_cron jobs | 13 rows in Supabase, 3 rogue | 10 versioned in `sql/cron/` | Excess ETL load; no version control |
| Credentials | In source tree | Rotated and in `.gitignore` only | Security risk |

---

## 5. Main Blockers

In dependency order — each row blocks everything below that depends on it.

| # | Blocker | What it blocks |
|---|---------|---------------|
| **B1** | Credentials in source tree + pg_cron rogue jobs | Should be fixed before any other work; security risk |
| **B2** | Storage abstraction not wired (`.bak` files not applied) | ML monorepo migration; `STORAGE_BACKEND=local`; client ML |
| **B3** | ML shell scripts redirect to legacy repo | B2 having any production effect; ML from monorepo |
| **B4** | `SUPABASE_DB_*` aliases missing in `dev.env` | `export_features_dense.py` when run from monorepo path |
| **B5** | `gh-train-biweekly/quarterly` on legacy `EnvironmentFile` | Full env system consolidation |
| **B6** | No production Dockerfiles (backend + frontend) | Portable images; client install; cloud production build |
| **B7** | Frontend auth uses Supabase JS | client-local login; removing `@supabase/supabase-js` |
| **B8** | ETL SQL functions not in client-runtime | Data ever being populated on client |
| **B9** | No scheduler design for client-local | ETL + planner running automatically on client |
| **B10** | `install.sh` not written | Client product not deliverable |

---

## 6. Execution Phases

---

### Phase 1 — Production Stabilization and Source-of-Truth Cleanup

**Objective:** Eliminate immediate risks and establish a clean baseline before any
code migration. Zero deployment downtime. Zero ML job restarts.

**Scope:**
- Disable pg_cron jobs #30, #38, #39 on Supabase (rogue every-minute triggers)
- Delete `lovabel .env corretto.json` (×2 repos) + `docs/operations/env-live.txt`
- Rotate Supabase `SUPABASE_SERVICE_ROLE_KEY` + DO Spaces `DO_SPACES_SECRET`
- Add `SUPABASE_DB_*=${PG_*}` aliases to `infra/env/dev.env` (5 lines)
- Delete 9 `.bak*` files from `/etc/systemd/system/`
- Delete `app/core/config.py.bak` + `app/api/v1/ops.py.bak` from `apps/backend/`
- Gitignore `parquet_cache/`, `models_v4/`, `priors_cache/`, `.bak*`, `__pycache__/`
- Delete duplicate `models_v4_backup/*.tgz` from monorepo (keep `/opt/greenhouse/` copy)
- Move 8 `blocco_*_migration.sql` files → `sql/migrations/001-008_*.sql`
- Write `sql/cron/pg_cron_canonical.sql` (10 correct jobs)
- Flatten `infra/systemd/current/` → `infra/systemd/`; write `install.sh`
- Archive `greenbrain-v2/docs/` → `docs/archive/greenbrain-v2/`
- Apply Wave 7B.3: `ml_ops` schema (2 tables + 3 views + 1 public view)

**Excluded scope:**
- No Docker restarts
- No systemd unit changes
- No code changes to running ML Python
- No Supabase schema changes (except disabling cron jobs)

**Deliverables:**
1. No credentials in source tree; keys rotated
2. pg_cron rogue jobs disabled; ETL runs only on correct schedule
3. `sql/migrations/` populated with 8 historical files
4. `sql/cron/pg_cron_canonical.sql` written
5. `infra/systemd/` flat with `install.sh`
6. `/ops/pipeline-status` + `/ops/family-runs` → HTTP 200 empty in client-runtime

**Dependencies:** None. All changes are additive or deletions.

**Validation criteria:**
- `SELECT cron.unschedule(30)` succeeds; ETL still runs correctly on remaining jobs
- `curl /api/v1/ops/pipeline-status` → `{"count": 0, "items": []}` in client-runtime
- `git status` shows no credential files tracked

**Risk:** Low — no running service is modified.
**Complexity:** Low — ~3–4 hours total.

---

### Phase 2 — Monorepo Consolidation

**Objective:** Make `apps/backend/`, `apps/frontend/`, and `apps/ml-worker/` the
single active source for all running code. End the split-brain between legacy paths
and monorepo.

**Scope:**
- Apply `.bak_phase2b_fix` → `apps/ml-worker/data_access_v1.py` (storage wiring, step 1)
- Smoke test: `PREDICT_LIMIT=1` with `STORAGE_BACKEND=supabase` — no behavior change expected
- Apply `.bak_phase2b` → `export_features_dense.py`
- Apply `.bak_phase2c` → `upload_priors_to_supabase.py` + `download_priors_from_supabase.py`
- Delete all `.bak_phase2*` files after successful smoke
- Fix ML shell scripts: replace `cd /opt/greenhouse/repo` with `cd $GH_REPO_DIR`
  in `run_predict_all.sh`, `run_train_missing.sh`, `run_daily_parquet_batches.sh`
- Update `GH_REPO_DIR` in `infra/env/dev.env` to `apps/ml-worker` monorepo path
- Migrate `gh-train-biweekly-all` + `gh-train-quarterly` `EnvironmentFile` → `load_env.sh`
- Update `WorkingDirectory` in both services to monorepo path
- Remove `/opt/greenhouse/bin/` from `$PATH` (after confirming `infra/scripts/bin/` is in PATH)
- Write `apps/backend/Dockerfile` (uvicorn production)
- Update `docker-compose.base.yml` backend volume → `apps/backend/`
- Copy `apps/frontend/.env` + `supabase/` from legacy path
- Update `docker-compose.base.yml` frontend volume → `apps/frontend/`

**Excluded scope:**
- Frontend auth replacement (Phase 5)
- Production frontend Dockerfile (Phase 7)
- ETL SQL porting to client-runtime (Phase 3)
- Archiving `/opt/greenhouse/repo/` (only after full daily cycle validated)

**Deliverables:**
1. All 6 systemd ML jobs run from `apps/ml-worker/`
2. `STORAGE_BACKEND=supabase` smoke test passes — prediction output identical to current
3. Docker backend serves from `apps/backend/`
4. Docker frontend serves from `apps/frontend/`
5. Single env system — `/opt/greenhouse/.env` no longer referenced by any active service
6. `apps/backend/Dockerfile` exists and builds

**Dependencies:** Phase 1 (`SUPABASE_DB_*` aliases added; `.bak` artifacts deleted from backend)

**Validation criteria:**
- `gh-predict-all` runs full cycle with `PREDICT_LIMIT=1` from monorepo path; output matches previous run
- `gh-train-biweekly-all` dry-run with `TRAIN_LIMIT=1` from monorepo + `load_env.sh`
- `docker exec gb_v2_backend curl /health` → 200 after compose update
- `journalctl -u gh-predict-all` shows `Working directory: .../apps/ml-worker`
- `grep -r /opt/greenhouse /etc/systemd/system/gh-*.service` returns nothing

**Risk:** High — ML jobs are production-critical. First run from new path must be validated
against output parity before declaring success.
**Complexity:** Medium — ~2 days. Sequential execution required (ML smoke before shell script change).

---

### Phase 3 — SQL + Analytics Canonicalization

**Objective:** Make `sql/` the versioned schema home. Complete client-runtime schema
coverage for all analytics, dashboard, and ops endpoints. Verify all 58 endpoints.

**Scope:**
- Export Supabase schema: `pg_dump --schema-only` → `sql/schema/supabase-snapshot.sql`
- Diff against `greenbrain-v2/database/current-schema.sql` to measure drift; document
- Write `sql/migrate.sh` (sequential apply with idempotency)
- Run endpoint smoke suite against client-runtime: record exact HTTP status for all 58
- Document which Wave 7B.2 sub-waves actually applied which Tier 3/4 objects
- Add `CREATE EXTENSION IF NOT EXISTS pg_trgm` to client-runtime bootstrap (catalog RPCs)
- Extract ETL plpgsql functions from Supabase → `sql/etl/` (read-only extraction, no rewrite)
- Review extracted ETL for Supabase-specific calls (`auth.*`, `vault.*`, `pgsodium`); neutralize
- Write Wave 7B.4: ETL functions for client-runtime (populates analytics + dashboard tables)
- Enable `pg_cron` extension in client Docker PostgreSQL compose
- Load ETL schedule for client-runtime (`sql/cron/client-variant.sql`)
- Verify analytics data is populated in client-runtime after one ETL run
- Verify BUSINESS-VALIDATED endpoints return non-empty data in client-runtime

**Excluded scope:**
- Planner RPCs (deferred until Phase 4 — requires ML forecast data)
- ML pipeline changes (Phase 4)
- Frontend auth (Phase 5)
- Full `ml_forecast` schema migration (deferred)

**Deliverables:**
1. `sql/schema/supabase-snapshot.sql` — live Supabase DDL in version control
2. `sql/migrate.sh` — idempotent migration runner
3. Schema drift between Supabase and local Docker documented
4. Endpoint smoke matrix: exact HTTP status for all 58 endpoints in client-runtime
5. Wave 7B.4 applied: ETL functions working in client-runtime
6. Client-runtime analytics endpoints return non-empty data after ETL run
7. `pg_trgm` extension active; catalog search RPCs functional

**Dependencies:** Phase 1 (credentials rotated; `sql/migrations/` populated; pg_cron jobs versioned)

**Validation criteria:**
- `SELECT refresh_core_analytics_range(...)` runs in client-runtime PostgreSQL without error
- `/api/v1/analytics/series?granularity=day&entity_type=famiglia` returns non-empty data
- `/api/v1/analytics/series-breakdown` returns non-empty data
- `/api/v1/dashboard/sales-weekly` returns non-empty data
- All 5 BUSINESS-VALIDATED endpoints return non-empty data in client-runtime
- Endpoint smoke: 53+/58 at HTTP 200 (planner RPCs deferred)

**Risk:** Medium — ETL function extraction may reveal Supabase-specific SQL (`gen_random_uuid()`,
PostgREST-specific JSON, `auth.uid()`). Each dependency must be neutralized manually.
**Complexity:** High — ~1 week. ETL extraction is the hardest step.

---

### Phase 4 — ML + ETL Portability

**Objective:** Make the ML pipeline fully runnable from monorepo with local storage
(`STORAGE_BACKEND=local`). No dependency on DO Spaces or Supabase Storage at runtime.

**Scope:**
- Validate `STORAGE_BACKEND=local` end-to-end on dev-cloud host with monorepo ML
  (requires Phase 2 storage wiring to be complete)
- Set `LOCAL_STORAGE_ROOT` env var; test full predict cycle writes to local filesystem
- Move `parquet_cache/` default outside repo tree (update `PARQUET_CACHE_DIR`)
- Design client-local ML scheduler: pg_cron for ETL (Phase 3 covers this);
  `cron` or `systemd` for ML training + prediction timers
- Write parametrized systemd unit templates for client-local ML
  (`WorkingDirectory`, `EnvironmentFile` as template variables)
- Archive `/opt/greenhouse/repo/` as read-only (only after one full daily production
  cycle confirmed from monorepo)
- Archive `/opt/greenhouse/venv/` (client uses its own venv built from `requirements.txt`)
- Document model refresh mechanism for client update cycle

**Excluded scope:**
- Frontend (Phase 5)
- Client packaging (Phase 6)
- Planner (planner tables populated by ML forecast — this phase makes that possible)

**Deliverables:**
1. Full ML predict cycle with `STORAGE_BACKEND=local`: parquet read from local FS,
   model from local FS, forecast written to local PostgreSQL
2. Parametrized systemd unit templates in `infra/systemd/templates/`
3. `/opt/greenhouse/repo/` archived (read-only or moved to `/opt/greenhouse/repo.archive/`)
4. `PARQUET_CACHE_DIR` outside repo; `.gitignore` updated
5. Client ML scheduler design documented

**Dependencies:** Phase 2 (all ML jobs from monorepo; storage wiring complete)

**Validation criteria:**
- `STORAGE_BACKEND=local PREDICT_LIMIT=1` predict cycle completes; `greenhouse_forecast_results_v2`
  row written to local PostgreSQL
- `ls /opt/greenhouse/repo/` shows archive marker, no active systemd service points there
- `grep -r /opt/greenhouse /etc/systemd/system/*.service` returns nothing active

**Risk:** High — first full ML cycle from `STORAGE_BACKEND=local` on real data is highest-risk
step. Model loading from local filesystem must be tested incrementally (1 family first).
**Complexity:** Medium — ~3 days. Dependent on Phase 2 full validation.

---

### Phase 5 — Frontend Auth Decoupling

**Objective:** Remove `@supabase/supabase-js` from the frontend entirely. Make auth work
via FastAPI JWT. Enable production frontend Docker image.

**Scope:**
- Implement in `apps/backend/app/api/v1/auth.py`:
  - `POST /api/v1/auth/login` — validates credentials, returns JWT
  - `GET /api/v1/auth/me` — returns current user from JWT
- Implement `GET /api/v1/settings/garden-center` in backend
  (replaces `useGardenCenterSettings` Supabase direct query)
- Replace `src/hooks/useAuth.tsx` with FastAPI JWT implementation
- Replace `src/hooks/useGardenCenterSettings.ts` with `apiClient.ts` call
- Remove `src/integrations/supabase/client.ts`
- Remove `@supabase/supabase-js` from `package.json`
- Resolve lock file conflict: choose `npm` or `bun`; delete the other lock file
- Write `apps/frontend/Dockerfile` (Vite `npm run build` + nginx)
- Update docker-compose frontend service to use built image instead of dev server

**Excluded scope:**
- Backend user management (user creation, password reset) — design after this phase
- Client packaging (Phase 6)

**Deliverables:**
1. `POST /api/v1/auth/login` working; JWT returned
2. Frontend login works without any Supabase dependency
3. `package.json` has no `@supabase/supabase-js`
4. `apps/frontend/Dockerfile` builds successfully; `npm run build` passes
5. `gb_v2_frontend` container runs production nginx build (not Vite dev server)
6. `VITE_SUPABASE_URL` + `VITE_SUPABASE_PUBLISHABLE_KEY` no longer required

**Dependencies:** Phase 2 (monorepo `.env` in `apps/frontend/`; Docker mount on monorepo path)

**Validation criteria:**
- Login flow works end-to-end in browser (enter credentials → dashboard loads)
- All frontend routes functional after login
- `docker inspect gb_v2_frontend` shows no `npm run dev` process
- `grep -r supabase apps/frontend/src/` returns nothing except config/types that are gone

**Risk:** High — auth is the critical path. Regression during transition means complete
frontend lockout. Requires feature-flag approach or staged rollout.
**Complexity:** Medium — ~3–4 days. Auth implementation is well-defined; Supabase removal is mechanical.

---

### Phase 6 — Client-Runtime Packaging

**Objective:** Create a fully working, installable client package. A new customer server
should go from zero to functional GreenBrain in one script.

**Scope:**
- Write `client-runtime/install.sh`:
  1. Check prerequisites (Docker, Docker Compose, Python 3.11+, available ports)
  2. `docker-compose up -d` (postgres + backend + frontend)
  3. Wait for postgres; apply `sql/init/` wave sequence in order
  4. Apply `CREATE EXTENSION pg_cron`; load `sql/cron/client-variant.sql`
  5. Create initial admin user (call `POST /api/v1/auth/setup` — to be added)
  6. Pull initial model bundles from remote source (or install from bundled media)
  7. Print health check URL and credentials
- Write `client-runtime/update.sh`:
  1. Pull latest Docker images
  2. Apply any new `sql/init/` wave files not yet applied (idempotent check)
  3. Refresh model bundles if newer version available
- Write `client-runtime/README.md` with install + update + backup runbook
- Write backup runbook: `pg_dump` cron for client PostgreSQL; model bundle backup
- Test cold install on clean Ubuntu 22.04 VM
- Define and document port layout, volume mounts, data retention policy

**Excluded scope:**
- Multi-tenant features
- Remote management / telemetry
- Customer-specific customization

**Deliverables:**
1. `install.sh` runs to completion on clean Ubuntu 22.04
2. After install: login works; analytics returns data; dashboard renders
3. `update.sh` applies new waves without data loss
4. Backup runbook documented and tested
5. `client-runtime/README.md` complete

**Dependencies:** Phases 3 + 4 + 5 (ETL portable; ML portable; auth decoupled from Supabase)

**Validation criteria:**
- Clean VM test: `git clone` + `./install.sh` → dashboard loads with data within 1 hour
- `./update.sh` with a new wave file applies cleanly without dropping data
- `pg_dump` backup + restore cycle completes without data loss

**Risk:** Medium — integration phase. Individual components validated in earlier phases;
risk is in interaction between install script and real hardware variation.
**Complexity:** Medium — ~3 days if all prerequisites complete.

---

### Phase 7 — Cloud Deployment Standardization

**Objective:** Complete cloud-side consolidation. All Docker containers mount monorepo
paths. Legacy external dirs archived. CI/CD pipeline in place.

**Scope:**
- Move `docker-compose.*.yml` from `/opt/greenbrain-v2/deploy/` → `infra/docker/`
- Update backend volume: `../backend:/app` → `/opt/greenbrain-platform/apps/backend:/app`
- Update frontend service: switch from volume mount to production image build
- Archive `/opt/greenbrain-v2/deploy/`
- Archive `/opt/greenbrain/frontend/` (after Docker mount confirmed on production image)
- Archive `/opt/greenbrain-v2/backend/`
- Write GitHub Actions (or equivalent) CI pipeline:
  - Lint + test on PR
  - Docker image build check
  - Schema migration dry-run
- Write cloud deploy runbook: how to push a new release
- Document `gb_v2_postgres` backup strategy (container volume is not backed up today)
- Remove dead `gb_v2_ml` container service from compose

**Excluded scope:**
- Multi-environment (staging) infrastructure — deferred post-Phase 7
- Kubernetes migration — not in scope

**Deliverables:**
1. All 6 Docker containers running from monorepo paths
2. `/opt/greenbrain-v2/` and `/opt/greenbrain/` archived (read-only)
3. CI pipeline: lint + Docker build check on every PR
4. Cloud deploy runbook: `git pull && docker-compose up -d --build`
5. `gb_v2_postgres` backup documented and automated

**Dependencies:** Phases 2 + 5 (monorepo is SoT; frontend auth not Supabase)

**Validation criteria:**
- `docker inspect gb_v2_backend | grep Source` shows `apps/backend`
- `docker inspect gb_v2_frontend | grep -i image` shows production image (not dev server)
- `ls /opt/greenbrain-v2/` shows `ARCHIVED` marker; no active service references it
- CI pipeline passes on a sample PR

**Risk:** Medium — Docker restarts during transition cause brief downtime.
**Complexity:** Low-medium — ~2 days. Mostly mechanical path updates and archive operations.

---

## 7. Recommended Next Wave

**Apply Wave 7B.3 (ml_ops schema) immediately.** It is the only schema wave that is
both simple (2 tables + 3 views) and independently applicable without any other change.

After that, the single highest-leverage action is **storage abstraction wiring** (Phase 2,
first step): apply `.bak_phase2b_fix` to `data_access_v1.py` and run a `PREDICT_LIMIT=1`
smoke test with `STORAGE_BACKEND=supabase`. This validates the migration pattern for all
remaining files without any production behavior change.

SQL to write for Wave 7B.3 (`client-runtime/sql/init/13_schema_7b3_ml_ops.sql`):
```sql
-- Wave 7B.3: ml_ops schema
CREATE SCHEMA IF NOT EXISTS ml_ops;

CREATE TABLE IF NOT EXISTS ml_ops.pipeline_run_log_v1 (
    run_id          TEXT PRIMARY KEY,
    job_type        TEXT,
    trigger_mode    TEXT,
    status          TEXT,
    started_at      TIMESTAMPTZ,
    finished_at     TIMESTAMPTZ,
    duration_min    NUMERIC(8,2),
    host_name       TEXT,
    rows_processed  INTEGER,
    error_message   TEXT,
    git_sha         TEXT,
    notes           TEXT
);

CREATE TABLE IF NOT EXISTS ml_ops.family_run_log_v1 (
    family_run_id   TEXT PRIMARY KEY,
    pipeline_run_id TEXT,
    job_type        TEXT,
    family_name     TEXT,
    demand_class_final TEXT,
    model_code      TEXT,
    started_at      TIMESTAMPTZ,
    finished_at     TIMESTAMPTZ,
    status          TEXT,
    rows_written    INTEGER,
    artifact_path   TEXT,
    error_message   TEXT,
    error_trace     TEXT
);

CREATE TABLE IF NOT EXISTS public.t_ops_pipeline_monitor (
    id      SERIAL PRIMARY KEY,
    snap_ts TIMESTAMPTZ NOT NULL DEFAULT now(),
    ok      BOOLEAN NOT NULL DEFAULT false
);

CREATE OR REPLACE VIEW ml_ops.v_pipeline_runs_recent_v1 AS
SELECT run_id, job_type, trigger_mode, status, started_at, finished_at,
       duration_min, host_name, rows_processed, error_message, git_sha, notes
FROM ml_ops.pipeline_run_log_v1
ORDER BY started_at DESC;

CREATE OR REPLACE VIEW ml_ops.v_daily_pipeline_summary_v1 AS
SELECT started_at::date AS day, job_type,
       count(*) AS runs,
       count(*) FILTER (WHERE status = 'ok') AS ok_runs,
       count(*) FILTER (WHERE status != 'ok') AS bad_runs
FROM ml_ops.pipeline_run_log_v1
GROUP BY 1, 2;

CREATE OR REPLACE VIEW public.v_ops_pipeline_status AS
SELECT id, snap_ts, ok FROM public.t_ops_pipeline_monitor;

INSERT INTO _runtime_bootstrap (wave, note)
VALUES ('wave-7b3', 'ml_ops schema: pipeline_run_log_v1, family_run_log_v1, ops views');
```

---

## 8. What Must NOT Be Touched Yet

Changes to these items before their phase prerequisites are met will break production.

| Item | Reason to wait | Wait for |
|------|---------------|----------|
| `/opt/greenhouse/repo/` Python files | Live source for 5/6 ML jobs; any change here is invisible after monorepo switch | Phase 2 complete + one full daily cycle from monorepo confirmed |
| `WorkingDirectory` in `gh-train-biweekly/quarterly` | Changing this while shell scripts still `cd` to legacy path causes `ModuleNotFoundError` | Phase 2: shell scripts fixed first, then WorkingDirectory |
| `EnvironmentFile=/opt/greenhouse/.env` removal | Two services depend on it entirely | Phase 2: all vars confirmed in `dev.env`; dry-run of both services |
| `docker-compose.base.yml` frontend volume | Changing to monorepo path while `.env` is missing in monorepo breaks the container | Phase 2: `.env` copied to `apps/frontend/` and `npm run build` confirmed |
| `docker-compose.base.yml` backend volume | If `apps/backend/` has stale imports or missing env, backend 500s immediately | Phase 2: `Dockerfile` built and `GET /health` confirmed from monorepo image |
| Supabase PostgreSQL live schema | No migration runner; no rollback; adding tables without versioning increases drift | Phase 3: `sql/migrate.sh` in place |
| pg_cron jobs #11, #12, #13, #28-37 (correct ETL jobs) | These are the active ETL and planner schedule; disabling any breaks data pipeline | Never change these without testing ETL output first |
| `@supabase/supabase-js` removal from frontend | Removing before FastAPI auth is implemented = immediate login failure for all users | Phase 5: `POST /api/v1/auth/login` live and tested |
| `/opt/greenbrain-v2/deploy/` docker-compose files | Cloud containers start from here; archiving while volume paths still reference it breaks all containers | Phase 7: volumes updated to monorepo; all containers confirmed healthy |
| Supabase `SUPABASE_SERVICE_ROLE_KEY` rotation | All parquet export and priors jobs depend on this; must update all env files simultaneously | Plan a maintenance window; update all 4 env files atomically |

---

## 9. Definition of Done

### Dev-cloud is done when:
- [ ] All Docker containers mount paths within `greenbrain-platform/`
- [ ] All 6 systemd ML jobs run from `apps/ml-worker/`; no reference to `/opt/greenhouse/repo/`
- [ ] Single env system: `infra/env/base.env + dev.env` via `load_env.sh` for all services
- [ ] `sql/` versioned with schema snapshot + 8 historical migrations + pg_cron canonical file
- [ ] `pg_cron` has exactly 10 canonical jobs; #30/38/39 permanently disabled
- [ ] No credentials in any tracked file; `.gitignore` covers all env files
- [ ] Frontend runs as production build (nginx); no Vite dev server in production
- [ ] Auth via FastAPI JWT; no `@supabase/supabase-js` in browser
- [ ] `/opt/greenbrain-v2/` and `/opt/greenbrain/` archived; no active service references them
- [ ] CI pipeline passes on every PR: lint + Docker build + migration dry-run

### Client-local is done when:
- [ ] `install.sh` completes on clean Ubuntu 22.04 in under 1 hour
- [ ] After install: login works; analytics returns real data; dashboard renders
- [ ] ETL runs on schedule (pg_cron in local Docker); `t_etl_runs` shows SUCCESS
- [ ] ML predict cycle runs locally: `STORAGE_BACKEND=local`; `greenhouse_forecast_results_v2` populated
- [ ] `update.sh` applies new schema waves and model bundles without data loss
- [ ] No internet dependency at runtime (Supabase, DO Spaces, DigitalOcean unreachable = still works)
- [ ] Auth via FastAPI JWT (same backend binary as dev-cloud)
- [ ] Backup + restore cycle documented and tested

### Analytics is done when:
- [ ] All 16 series endpoints return HTTP 200 in client-runtime ✅ (already done)
- [ ] All 5 BUSINESS-VALIDATED endpoints (`series-breakdown`, `future-windows-stats`,
      `compare-series`, `entity-summary`, `reorder-suggestions`) return non-empty data in client-runtime
- [ ] ETL runs in client-runtime; data refreshes nightly automatically
- [ ] Breakdown endpoints return data for at least 3 granularities × 3 entity types
- [ ] `dashboard/kpis` either implemented or explicitly accepted as deferred stub with written rationale

### ML is done when:
- [ ] All 6 systemd jobs run from `apps/ml-worker/` with `STORAGE_BACKEND=supabase`; output parity confirmed
- [ ] `STORAGE_BACKEND=local` predict cycle completes end-to-end on client machine
- [ ] No reference to `/opt/greenhouse/` in any active systemd unit or shell script
- [ ] Model bundles refreshable via `update.sh` without manual intervention
- [ ] `ml_ops` schema written to local PostgreSQL on every train/predict run

### Frontend is done when:
- [ ] Production Docker image (`Dockerfile` + nginx) builds and serves the app
- [ ] No `@supabase/supabase-js` in `package.json`
- [ ] Login works via FastAPI JWT in both dev-cloud and client-local
- [ ] Single lock file (either `package-lock.json` or `bun.lock`; the other deleted)
- [ ] `VITE_API_BASE_URL` is the only mode-specific env var required at build time
- [ ] Vite dev server (`npm run dev`) used only for local development, never in Docker

### Deploy / install is done when:
- [ ] `apps/backend/Dockerfile` builds production uvicorn image
- [ ] `apps/frontend/Dockerfile` builds production Vite + nginx image
- [ ] `infra/docker/docker-compose.base.yml` has no legacy volume paths
- [ ] `client-runtime/install.sh` produces a working system from zero
- [ ] `client-runtime/update.sh` handles schema + model updates without data loss
- [ ] CI pipeline: lint + build + schema migration dry-run on every PR
- [ ] Cloud deploy runbook: one command (`docker-compose up -d --build`) with tested rollback

---

*Cross-reference: `docs/architecture/dev-cloud-vs-client-local.md` · `docs/migration/source-of-truth.md` · `docs/migration/migration-map.md` · `docs/architecture/runtime-current-state.md`*
