# GreenBrain — Canonical Architecture
> Single authoritative reference for the current real system state, source-of-truth
> decisions, and target architecture for the full GreenBrain product.
> Updated: 2026-04-02.
>
> Primary evidence sources:
> `docs/analysis-stato-sistema-2026-04.md` ·
> `docs/migration/source-of-truth.md` ·
> `docs/migration/migration-map.md` ·
> `docs/architecture/dev-cloud-vs-client-local.md` ·
> `docs/architecture/master-roadmap-to-product.md` ·
> `docs/architecture/runtime-current-state.md` ·
> `docs/operations/00-full-system-inventory-0{1,2,3}.md`

---

## 1. Product Definition

GreenBrain is one product with two execution modes:

- **dev-cloud** — runs on a DigitalOcean cloud host. Used for active development,
  ML training, ETL, forecasting, and all operational analytics. The Supabase cloud
  PostgreSQL instance is the live ML/ETL data store. A local Docker PostgreSQL
  instance (`gb_v2_postgres`) serves the FastAPI backend and frontend.

- **client-local** — runs on a customer's Linux server. No Supabase account, no
  DigitalOcean dependency, no internet required at runtime. Schema loaded from
  versioned init waves. ML pipeline and ETL run locally against a local PostgreSQL
  instance.

**client-local is not a different product. It is the same product running in a
different infrastructure configuration.**

The code is shared. The infrastructure config is not.

---

## 2. The Current Hybrid Reality

The system is not yet in its target state. Code, configuration, and data are
currently split across multiple locations. This is the actual topology today:

```
/opt/greenbrain-platform/     ← monorepo (target SoT for all code)
/opt/greenbrain-v2/backend/   ← Docker-mounted backend (LIVE — legacy path)
/opt/greenbrain/frontend/     ← Docker-mounted frontend (LIVE — legacy path)
/opt/greenhouse/repo/         ← 5 of 6 ML systemd jobs still run from here (LIVE)
apps/ml-worker/               ← 1 ML job runs from here (gh-refresh-registry)
Supabase cloud PostgreSQL     ← ETL writes here; pg_cron runs here
gb_v2_postgres (Docker)       ← FastAPI reads from here (schema snapshot, not ETL)
```

These two databases — Supabase cloud and `gb_v2_postgres` — are not the same.
The frontend and API serve data from the local Docker DB, which is populated from
a manual schema snapshot, not live ETL output.

---

## 3. Domain-by-Domain Canonical State

---

### 3.1 Backend

| | |
|---|---|
| **Running now** | Docker `gb_v2_backend :8002`, source volume mounted from `/opt/greenbrain-v2/backend/` |
| **Current SoT** | `apps/backend/` in monorepo (kept in sync manually; no divergence confirmed) |
| **Idle copies** | `/opt/greenbrain-v2/backend/` is the live-mounted copy, not the SoT |
| **Target** | Docker container mounts `apps/backend/`; production `Dockerfile` in `apps/backend/` |
| **Status** | **Hybrid** — code is correct; path is wrong |

The FastAPI backend has no Supabase SDK dependency. All DB access is via
SQLAlchemy over `POSTGRES_*` env vars. The same binary runs correctly in both
execution modes. **No backend code changes are required for client-local.**

Missing: `apps/backend/Dockerfile` (production uvicorn image).

---

### 3.2 Frontend

| | |
|---|---|
| **Running now** | Docker `gb_v2_frontend :8083`, Vite **dev server** (`npm run dev`), source from `/opt/greenbrain/frontend/` |
| **Current SoT** | `apps/frontend/` in monorepo |
| **Idle copies** | `/opt/greenbrain/frontend/` is the live-mounted copy |
| **Target** | Production Docker image: Vite build + nginx; auth via FastAPI JWT |
| **Status** | **Hybrid + blocked** — dev server in production; Supabase auth dependency |

All data hooks (`src/hooks/`) already call `apiClient.ts` → FastAPI. The only
remaining Supabase dependency is auth: `src/integrations/supabase/client.ts`,
`src/hooks/useAuth.tsx`, `src/hooks/useGardenCenterSettings.ts`.

Lock file conflict: both `package-lock.json` and `bun.lock` are present.

Missing: `apps/frontend/Dockerfile`; FastAPI JWT auth endpoints; `useAuth.tsx`
replacement; `useGardenCenterSettings` FastAPI endpoint.

---

### 3.3 Auth

| | |
|---|---|
| **Running now** | Supabase JS auth in browser (`integrations/supabase/client.ts`) |
| **Current SoT** | Supabase cloud (`VITE_SUPABASE_URL` + JWT) |
| **Idle copies** | None — no alternative auth exists yet |
| **Target** | FastAPI JWT: `POST /api/v1/auth/login`, `GET /api/v1/auth/me` |
| **Status** | **Blocked** — auth is cloud-only; client-local login is impossible |

This is the single hardest user-facing blocker for client-local. Removing
`@supabase/supabase-js` before FastAPI JWT is live causes immediate login failure.

---

### 3.4 ML Pipeline

| | |
|---|---|
| **Running now** | 5 of 6 systemd jobs: `WorkingDirectory=/opt/greenhouse/repo/`; 1 job (`gh-refresh-registry`) from monorepo |
| **Current SoT** | `apps/ml-worker/` in monorepo |
| **Idle copies** | `/opt/greenhouse/repo/` is the live source for training and prediction |
| **Target** | All 6 jobs from `apps/ml-worker/`; `STORAGE_BACKEND` env var controls storage |
| **Status** | **Hybrid + blocked** — storage abstraction written but not wired |

Storage abstraction module (`apps/ml-worker/storage/`) is complete:
`LocalStorageBackend`, `S3StorageBackend`, `SupabaseStorageBackend`, `backend.py`
factory. However, 4 calling files still use direct SDK calls:
`data_access_v1.py`, `export_features_dense.py`, `upload_priors_to_supabase.py`,
`download_priors_from_supabase.py`. Migration files (`.bak_phase2b/2c`) exist but
are not yet applied.

Shell scripts for all ML jobs redirect to `/opt/greenhouse/repo/` via hardcoded
`cd`. Until shell scripts and `WorkingDirectory` are updated, the storage
abstraction has zero production effect.

Two services (`gh-train-biweekly-all`, `gh-train-quarterly`) use
`EnvironmentFile=/opt/greenhouse/.env` instead of `load_env.sh`.

---

### 3.5 SQL / Schema / Migrations

| | |
|---|---|
| **Running now** | Supabase cloud PostgreSQL (live ETL data); `gb_v2_postgres` local Docker (API/frontend, schema snapshot) |
| **Current SoT** | Supabase cloud PostgreSQL — it is the only fully populated, live-ETL-fed database |
| **Idle copies** | `greenbrain-v2/database/current-schema.sql` (snapshot, drift status unknown) |
| **Target** | `sql/` directory versioned; `sql/migrate.sh` for ordered application; same DDL in both modes |
| **Status** | **Hybrid** — two live databases; no migration runner; `sql/` directory is empty |

Historical migration files (`blocco_*_migration.sql`) are in
`apps/backend/app/api/v1/jobs/migrations/` — incorrect location; not yet moved
to `sql/migrations/`.

pg_cron canonical state: 13 jobs in Supabase, of which 3 (#30, #38, #39) are
rogue every-minute duplicates. These must be disabled. The 10 correct jobs are
not yet versioned in `sql/cron/`.

Client-runtime schema: **13 sequential init files applied** (`client-runtime/sql/init/`),
covering Wave 7A (Tier 0/1) + Wave 7B.1 (Tier 2, 27 endpoints) + Wave 7B.2A-J
(Tier 3/4, partial) + Wave 7B.3 (ml_ops). The `_runtime_bootstrap` marker table
records each applied wave.

---

### 3.6 Analytics

> **Analytics is a first-class, central component of the GreenBrain product —
> not an optional appendix.** The entire frontend relies on analytics data.
> The planner depends on analytics forecasts. ETL feeds analytics tables nightly.

| | |
|---|---|
| **Running now** | `apps/backend/app/api/v1/analytics.py` router; served by `gb_v2_backend` |
| **Current SoT** | Dev-cloud: Supabase PostgreSQL (populated by ETL). Client-runtime: same schema, data empty |
| **Idle copies** | None — the analytics router is active in both modes |
| **Target** | Same router in both modes; ETL populates local PostgreSQL in client-local |
| **Status** | **Real in dev-cloud; schema-only in client-runtime** |

Full analytics domain covers:
- 16 `t_core_analytics__series_*` tables (one per granularity × entity type)
- 16 corresponding `*_lc` views (used by API endpoints)
- 12 `t_core_analytics__breakdown_*` tables + views
- `t_core_analytics__seasonality_month` table + view
- 7 analytics RPCs (`range_totals_v2`, `stock_and_reorder_v1`, `future_window_stats_v2`,
  `compare_series_daily_total`, `entity_hierarchy_tree_v1`, plus supporting functions)

All schema objects are present in client-runtime init files. Data is absent because
the ETL plpgsql functions are not yet ported to client-runtime.

---

### 3.7 Dashboard

| | |
|---|---|
| **Running now** | `apps/backend/app/api/v1/dashboard.py` router; `t_dashboard_sales_*` tables via ETL |
| **Current SoT** | Supabase PostgreSQL (ETL-populated) for dev-cloud; stubs in client-runtime |
| **Target** | Same: ETL populates local PostgreSQL in client-local |
| **Status** | **Real in dev-cloud; schema stubs in client-runtime** |

Dashboard domain: 4 aggregation tables (`t_dashboard_sales_{daily,weekly,monthly,yearly}`),
3 views, `dashboard__kpis_v2()` function, `dashboard__reorder_suggestions_top` join view.

`dashboard/reorder-suggestions` is **REAL / BUSINESS-VALIDATED** in dev-cloud.
`dashboard/kpis` is accepted as a safe stub for the current phase.

---

### 3.8 Planner

| | |
|---|---|
| **Running now** | `apps/backend/app/api/v1/planner.py` router; `nightly_roll4_tick()` via pg_cron (Supabase) |
| **Current SoT** | Supabase PostgreSQL (9 planner tables, 8 RPCs, scheduler job) |
| **Target** | Same schema on client; pg_cron in local Docker PostgreSQL; ML forecast data feeds planner |
| **Status** | **Partial in client-runtime** — tolerant endpoints work; RPCs absent |

In client-runtime:
- `/planner/calendar-events` → 200 empty (tolerant, catches ProgrammingError) ✅
- `/planner/current-week` → accepted safe stub ✅
- All other planner endpoints → 500 (8 planner RPCs not yet in init files)

Planner RPCs require ML forecast data (`greenhouse_forecast_results_v2` populated).
They are deferred until the ML pipeline is portable.

---

### 3.9 Ops

| | |
|---|---|
| **Running now** | `apps/backend/app/api/v1/ops.py` router; `ml_ops` schema on Supabase (written by ML jobs) |
| **Current SoT** | Supabase PostgreSQL `ml_ops` schema for dev-cloud; Wave 7B.3 init file for client-runtime |
| **Target** | Same `ml_ops` schema in both modes; ML jobs write to local PostgreSQL in client-local |
| **Status** | **Real in dev-cloud; schema present but empty in client-runtime** |

Wave 7B.3 (`client-runtime/sql/init/13_schema_7b3_ml_ops.sql`) is **applied and working**:
- `/api/v1/ops/health` → `ok` ✅
- `/api/v1/ops/pipeline-status` → 200 (schema present, data empty — ML jobs not yet writing locally) ✅
- `/api/v1/ops/family-runs` → 200 (schema present, data empty) ✅

Data will populate once ML jobs are ported to run locally with `STORAGE_BACKEND=local`.

---

### 3.10 Environment / Config

| | |
|---|---|
| **Running now** | 4 parallel env systems: `infra/env/dev.env` (4 services), `/opt/greenhouse/.env` (2 ML services), Docker `.env`, `apps/frontend/.env` (legacy path) |
| **Current SoT** | Split — no single env SoT |
| **Idle copies** | `infra/env/dev.env.bak_wave2`, `dev.env.bak_wave3` (archived backups, safe to delete) |
| **Target** | `infra/env/base.env + dev.env` via `load_env.sh` for all 6 services; `infra/env/client.env` for client-local |
| **Status** | **Hybrid** — 2 of 6 services bypass monorepo env entirely |

`infra/env/client.env` template exists with correct client-local overrides
(`STORAGE_BACKEND=local`, `PG_HOST=localhost`, no Supabase vars).

Security: credential files (`lovabel .env corretto.json`, `docs/operations/env-live.txt`)
are present in the source tree. Must be deleted and keys rotated before any exposure.

---

### 3.11 Systemd / Scheduler

| | |
|---|---|
| **Running now** | 6 systemd timers on cloud host: `gh-parquet-export`, `gh-refresh-registry`, `gh-train-missing`, `gh-predict-all`, `gh-train-biweekly-all`, `gh-train-quarterly` |
| **Current SoT** | `infra/systemd/` in monorepo (canonical versions); deployed files at `/etc/systemd/system/gh-*.{service,timer}` |
| **Idle copies** | `/etc/systemd/system/*.bak*` (9 backup files — safe to delete) |
| **Target** | All 6 units from monorepo; parametrized templates for client-local equivalent |
| **Status** | **Hybrid** — units deployed but 5/6 still point to legacy repo path |

pg_cron (Supabase): 13 jobs. 10 are correct ETL + planner triggers. 3 (#30, #38, #39)
are rogue every-minute duplicates that must be disabled.

Client-local scheduler: not yet designed. pg_cron extension can be enabled in the
local Docker PostgreSQL instance (`CREATE EXTENSION pg_cron`). ML timing will use
systemd timers or cron on the client host.

---

### 3.12 Docker / Deploy

| | |
|---|---|
| **Running now** | `docker-compose.base.yml` + `docker-compose.dev.yml` from `/opt/greenbrain-v2/deploy/`; 5 containers active (`gb_v2_backend`, `gb_v2_frontend`, `gb_v2_nginx`, `gb_v2_postgres`, `gb_v2_pgadmin`); `gb_v2_ml` is `sleep infinity` (dead placeholder) |
| **Current SoT** | `/opt/greenbrain-v2/deploy/` (compose files); `infra/docker/` in monorepo (target, not yet active) |
| **Idle copies** | `infra/docker/` contains target compose files not yet used for production |
| **Target** | All compose files from `infra/docker/`; backend and frontend as production images |
| **Status** | **Hybrid** — compose files in legacy path; volume mounts point to legacy source dirs |

Neither `apps/backend/Dockerfile` nor `apps/frontend/Dockerfile` exist. The backend
runs from a volume mount. The frontend runs from a Vite dev server, not a production
build.

Client-runtime Docker: `client-runtime/docker/docker-compose.yml` exists and is
correct. Used as the install base for client-local.

---

### 3.13 Client-Runtime

| | |
|---|---|
| **Running now** | Schema applied via 13 init files; `gb_v2_backend` serving from `client-runtime/docker/` compose |
| **Current SoT** | `client-runtime/` directory in monorepo |
| **Target** | Full install via `client-runtime/install.sh` (not yet written) |
| **Status** | **Functional subset** — schema bootstrapped; most endpoints 200; data empty |

Applied init waves:
| File | Wave | Coverage |
|------|------|----------|
| `01_bootstrap.sql` | 7A | `_runtime_bootstrap` marker; system tables |
| `02_schema_7b1.sql` | 7B.1 | 23 tables + 20 views → 27 endpoints at 200 |
| `03–12_schema_7b2{a-j}.sql` | 7B.2A-J | Tier 3/4 analytics, dashboard, catalog RPCs |
| `13_schema_7b3_ml_ops.sql` | 7B.3 | `ml_ops` schema: pipeline_run_log, family_run_log, monitor views |

Still absent from init files: ETL plpgsql functions (deferred — Wave 7B.4), 8 planner
RPCs (deferred — pending ML forecast portability), `ml_forecast` schema (deferred).

Not yet written: `install.sh`, `update.sh`.

---

## 4. Analytics Endpoint Validation State

Analytics is fully integrated into the product, not optional. The frontend renders
analytics charts, the planner uses analytics forecasts, and the ops layer monitors
analytics pipeline health. The following is the authoritative validation state.

### Business-validated in dev-cloud (REAL, non-empty, correct semantics)

| Endpoint | Validation status | Note |
|----------|------------------|------|
| `GET /api/v1/analytics/series-breakdown` | **REAL / BUSINESS-VALIDATED** | Confirmed non-empty for famiglia / categoria / fascia across day-week-month-year |
| `GET /api/v1/analytics/future-windows-stats` | **REAL / BUSINESS-VALIDATED** | Historical seasonal data confirmed non-empty |
| `GET /api/v1/analytics/compare-series` | **REAL / SEMANTICALLY-ACCEPTED** | Per-fascia multi-row output per date accepted as correct contract |
| `GET /api/v1/analytics/entity-summary` | **REAL / STRUCTURE-VALIDATED** | Tree-only hierarchical navigation; quantitative totals deferred |
| `GET /api/v1/dashboard/reorder-suggestions` | **REAL / BUSINESS-VALIDATED** | Edge cases validated: high/low stock × high/low forecast |
| `GET /health`, `GET /health/db`, `GET /system/db-info` | **REAL** | Infrastructure; always required |

### Returning HTTP 200 in client-runtime (schema present, data empty)

Data is absent because ETL does not yet run in client-local. These endpoints will
return real data once Wave 7B.4 (ETL functions) is applied and the ETL scheduler runs.

| Endpoint group | Wave | Status |
|----------------|------|--------|
| `/api/v1/analytics/series` (all granularities × entity types) | 7B.1 | 200 empty ✅ |
| `/api/v1/analytics/series-bounds` | 7B.1 | 200 empty ✅ |
| `/api/v1/analytics/seasonality` | 7B.1 | 200 empty ✅ |
| `/api/v1/analytics/future-windows` | 7B.1 | 200 empty ✅ |
| `/api/v1/dashboard/sales-{weekly,monthly,yearly}` | 7B.1 | 200 empty ✅ |
| `/api/v1/forecast/summary`, `/forecast/series`, `/forecast/sample` | 7B.1 | 200 empty ✅ |
| `/api/v1/analytics/series-breakdown` (RPCs + views) | 7B.2 | 200 empty ✅ |
| `/api/v1/analytics/range-totals` | 7B.2B | 200 empty ✅ |
| `/api/v1/analytics/stock-and-reorder` | 7B.2B | 200 empty ✅ |
| `/api/v1/analytics/future-windows-stats` | 7B.2 | 200 empty ✅ |
| `/api/v1/analytics/compare-series` | 7B.2 | 200 empty ✅ |
| `/api/v1/analytics/entity-summary` | 7B.2 | 200 empty ✅ |
| `/api/v1/dashboard/reorder-suggestions` | 7B.2C | 200 empty ✅ |
| `/api/v1/ops/health` | 7B.3 | `ok` ✅ |
| `/api/v1/ops/pipeline-status` | 7B.3 | 200 empty ✅ |

### Accepted stubs (HTTP 200, will remain empty until explicit work)

These are accepted as safe stubs for the current phase. They are not blocked by
ETL — they require separate implementation work.

| Endpoint | Reason empty | Unblocked by |
|----------|-------------|-------------|
| `GET /api/v1/dashboard/kpis` | `dashboard__kpis_v2()` function semantics deferred | Future explicit phase |
| `GET /api/v1/planner/current-week` | Pure date-math RPC; safe stub accepted | Already acceptable |
| `GET /api/v1/catalog/*` | Catalog enrichment deferred; basic families available | Explicit future wave |

### Deferred (not in any current init wave)

| Object group | Why deferred | Required for |
|---|---|---|
| ETL plpgsql functions (6 functions) | Most complex port; needs scheduler design | Analytics/dashboard data on client |
| 8 planner RPCs | Require ML forecast data populated | Planner on client |
| `ml_forecast` schema | ML pipeline not portable yet | ML routing |
| pg_cron ETL schedule | Needs pg_cron extension enabled in client Docker | ETL automation on client |

---

## 5. Summary Table

| Domain | Current real SoT | Target SoT | Current status | Blocking issues | Next required action |
|--------|-----------------|-----------|---------------|-----------------|---------------------|
| **backend** | `apps/backend/` (manually synced) | `apps/backend/` (Docker-mounted) | Hybrid — code correct, path wrong | No production `Dockerfile` | Write `apps/backend/Dockerfile`; update compose volume |
| **frontend** | `apps/frontend/` (manually synced) | `apps/frontend/` (production build) | Hybrid — dev server in production; Supabase auth | No production `Dockerfile`; Supabase JS in auth | Phase 5: FastAPI JWT first; then `Dockerfile` |
| **auth** | Supabase JS cloud auth | FastAPI JWT (`/api/v1/auth/`) | Blocked — client-local login impossible | `POST /api/v1/auth/login` not implemented | Implement FastAPI JWT endpoints |
| **ML pipeline** | `/opt/greenhouse/repo/` (5/6 jobs) | `apps/ml-worker/` (all jobs) | Hybrid — storage abstraction written but not wired | `.bak_phase2b/2c` not applied; shell scripts redirect to legacy | Apply `.bak_phase2b_fix` to `data_access_v1.py`; smoke test |
| **SQL / schema** | Supabase cloud (live ETL) + local Docker snapshot (API) | `sql/` versioned; `sql/migrate.sh`; same DDL both modes | Hybrid — two live DBs; no migration runner | `sql/` empty; 8 migration files misplaced; pg_cron jobs not versioned | Move 8 migration files; write `sql/migrate.sh`; write `sql/cron/pg_cron_canonical.sql` |
| **analytics** | Supabase cloud (ETL-populated) | Same DDL in both modes; ETL populates local DB in client-local | Real in dev-cloud; schema stubs in client-runtime | ETL functions not yet ported; no scheduler on client | Wave 7B.4: extract + port ETL plpgsql functions |
| **dashboard** | Supabase cloud (ETL-populated) | Same DDL in both modes | Real in dev-cloud; schema stubs in client-runtime | ETL absent on client; `dashboard__kpis_v2` stub | ETL porting (same as analytics) |
| **planner** | Supabase cloud + pg_cron | Same DDL + pg_cron in local Docker | Partial in client-runtime | 8 RPCs missing; no scheduler; no ML forecast data on client | Blocked until ML pipeline portable |
| **ops** | Supabase cloud `ml_ops` schema | Same schema in both modes; ML jobs write locally | Real in dev-cloud; schema present in client-runtime (Wave 7B.3 ✅) | ML jobs not writing to local `ml_ops` yet | Complete after ML portability (Phase 4) |
| **env / config** | Split: `infra/env/dev.env` (4 svc) + `/opt/greenhouse/.env` (2 svc) + Docker `.env` + frontend `.env` | `infra/env/base.env + dev.env` via `load_env.sh` for all 6 | Hybrid — 2 services on legacy env | Credentials in source tree; `SUPABASE_DB_*` aliases missing | Delete credentials + rotate; add `SUPABASE_DB_*` aliases; migrate biweekly/quarterly |
| **systemd** | `/etc/systemd/system/gh-*.{service,timer}` (deployed); 5/6 point to legacy repo | `infra/systemd/` as SoT; `WorkingDirectory` = monorepo | Hybrid — units deployed but wrong path | Shell scripts redirect to legacy; 9 `.bak*` files to delete | Fix shell scripts; update `WorkingDirectory`; delete `.bak*` files |
| **docker / deploy** | `/opt/greenbrain-v2/deploy/` (compose files in production use) | `infra/docker/` (compose); production `Dockerfile` per app | Hybrid — compose from legacy path; volume mounts legacy dirs | No production Dockerfiles; compose volumes on legacy paths | Write Dockerfiles; update compose volumes |
| **client-runtime** | `client-runtime/sql/init/` (13 waves applied) | `client-runtime/install.sh` + `update.sh` | Schema bootstrapped; endpoints 200; data empty | No ETL; no install script; no ML | Wave 7B.4 (ETL); `install.sh`; auth; ML portability |

---

## 6. Active Blockers (Priority Order)

1. **[SECURITY] Credentials in source tree** — `lovabel .env corretto.json` (×2) +
   `docs/operations/env-live.txt`. Delete + rotate Supabase JWT + DO Spaces secret.
   Zero-risk. Do this first.

2. **[STABILITY] pg_cron jobs #30/38/39** — every-minute rogue ETL triggers on
   Supabase. `SELECT cron.unschedule(30); cron.unschedule(38); cron.unschedule(39);`
   Five minutes. No deployment impact.

3. **[PORTABILITY] Storage abstraction not wired** — 4 ML files still call Supabase
   SDK directly. `.bak_phase2b/2c` files are ready. Apply `data_access_v1.py` fix first;
   smoke test with `PREDICT_LIMIT=1 STORAGE_BACKEND=supabase`; then apply remaining 3.

4. **[PORTABILITY] ML shell scripts redirect to legacy** — `run_predict_all.sh` and
   others hardcode `cd /opt/greenhouse/repo`. Fix `GH_REPO_DIR` in `dev.env`, then
   replace `cd /opt/greenhouse/repo` with `cd $GH_REPO_DIR` in all 3 scripts.

5. **[PORTABILITY] No production Dockerfiles** — `apps/backend/Dockerfile` and
   `apps/frontend/Dockerfile` do not exist. Blocks production images and client install.

6. **[CLIENT-LOCAL] Frontend auth = Supabase JS** — client-local login is
   impossible until FastAPI JWT is implemented and `useAuth.tsx` is replaced.

7. **[CLIENT-LOCAL] ETL functions not in client-runtime** — analytics, dashboard,
   and forecast tables are always empty on client. Wave 7B.4 required.

8. **[CLIENT-LOCAL] No scheduler for client** — pg_cron extension not yet enabled
   in client Docker PostgreSQL; no ML timer design.

9. **[CLIENT-LOCAL] `install.sh` not written** — client product is not deliverable.
   Blocked by all items above.

---

*For the migration sequence and phase-by-phase plan, see
`docs/architecture/master-roadmap-to-product.md`.*
*For the component comparison table, see
`docs/architecture/dev-cloud-vs-client-local.md`.*
*For individual domain SoT decisions, see
`docs/migration/source-of-truth.md`.*

---

## Note on Domain and Access Strategy

The confirmed domain model (`greenbrain.it` / `app.greenbrain.it` /
`<slug>.greenbrain.it`) and per-install auth strategy are accepted architectural
decisions. They do not take execution priority over platform completion.
Execution sequence: platform → domain rollout → customer remote access.
See `docs/architecture/final-platform-priority-and-access-decision.md`.
