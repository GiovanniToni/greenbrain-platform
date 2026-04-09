# GreenBrain — Dev-Cloud vs Client-Local Architecture
> Canonical comparison of the two intended execution modes.
> Updated: 2026-04-01. Evidence-based only.
> Cross-reference: `docs/architecture/separation-boundary.md` · `docs/migration/source-of-truth.md` · `docs/architecture/runtime-current-state.md`

---

## 1. Purpose

GreenBrain is a single product with two deployment targets:

- **dev-cloud** — the cloud droplet (DigitalOcean) where code is developed, ML
  pipelines run, and the full analytics/forecast/planner stack is populated with
  real data.
- **client-local** — an installable runtime that runs on a garden-center's own
  server, with no Supabase account, no DigitalOcean dependency, and no internet
  required at runtime.

This document defines what each mode means architecturally, where they already
converge, and what work remains to close the gap.

---

## 2. Shared Codebase Principle

> "The code is shared. The infrastructure config is not."
> — `docs/architecture/separation-boundary.md`

The entire application layer lives in `greenbrain-platform/`:

```
apps/backend/       FastAPI app          same binary in both modes
apps/frontend/      React app            same build in both modes
apps/ml-worker/     Python ML jobs       same code in both modes
client-runtime/     install package      client-local packaging only
infra/              systemd, env, docker mode-specific configuration
sql/                schema, migrations   same DDL, different execution path
```

The two modes differ only in:
1. **Where PostgreSQL is** (Supabase cloud vs local Docker)
2. **How storage works** (Supabase Storage + DO Spaces vs local filesystem)
3. **How auth works** (Supabase JS vs FastAPI JWT — not yet implemented)
4. **How the scheduler works** (systemd + pg_cron vs portable equivalent — not yet designed)
5. **How the stack is installed** (`docker-compose up` manually vs `install.sh` — not yet written)

Everything else — API logic, SQL schema, ML algorithms, React components, analytics
views, planner RPCs — is identical or must become identical.

---

## 3. Dev-Cloud Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  Cloud Droplet (DigitalOcean, Ubuntu)                                        │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │  Docker (gb_v2_* stack)                                                 │ │
│  │  gb_v2_backend  :8002   FastAPI (SQLAlchemy → gb_v2_postgres)           │ │
│  │  gb_v2_frontend :8083   Vite dev-server (npm run dev) — NOT production  │ │
│  │  gb_v2_nginx    :8082   Reverse proxy                                   │ │
│  │  gb_v2_postgres :5433   PostgreSQL 17 (local Docker, schema snapshot)   │ │
│  │  gb_v2_pgadmin  :5050   DB admin UI                                     │ │
│  │  gb_v2_ml       dead    sleep infinity — placeholder only               │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │  systemd ML timers (host, from /opt/greenhouse/repo/ — still legacy)    │ │
│  │  gh-parquet-export    21:35  ETL → Supabase Storage (parquet)           │ │
│  │  gh-refresh-registry  00:45  ML model registry refresh                  │ │
│  │  gh-train-missing     01:10  Incremental model training                 │ │
│  │  gh-predict-all       01:30  Daily forecast generation                  │ │
│  │  gh-train-biweekly    Sun 1+15 02:00  Full training cycle               │ │
│  │  gh-train-quarterly   1 Jan/Apr/Jul/Oct 02:30  Quarterly training       │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │  External Cloud Services                                                │ │
│  │  Supabase PostgreSQL      aws-1-eu-west-1  Live schema + ETL data       │ │
│  │  Supabase Storage         ml-snapshots     Parquet features + priors    │ │
│  │  DO Spaces                greenbrainmodels Model .pkl bundles           │ │
│  │  Supabase pg_cron         13 jobs          ETL + planner scheduler      │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Current anomaly:** the FastAPI backend reads from `gb_v2_postgres` (local Docker),
while the ML pipeline writes to Supabase cloud PostgreSQL. These are two separate
databases. The analytics/dashboard/planner data in the frontend is served from the
local Docker DB, which is populated by a manual schema snapshot — not live ETL output.

---

## 4. Client-Local Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  Client Server (Linux, single-tenant, no internet required at runtime)       │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │  Docker (client-runtime stack)                                          │ │
│  │  gb_v2_backend  :8002   FastAPI (same image as dev-cloud)               │ │
│  │  gb_v2_postgres :5433   PostgreSQL 17 (local, schema from init waves)   │ │
│  │  gb_v2_frontend [planned] React app (production build + nginx)          │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │  Local filesystem                                                       │ │
│  │  LOCAL_STORAGE_ROOT/    Parquet features, priors, model bundles         │ │
│  │  (replaces Supabase Storage + DO Spaces)                                │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │  Scheduler [NOT YET DESIGNED]                                           │ │
│  │  pg_cron extension   ETL + planner refresh (needs local equivalent)     │ │
│  │  cron / systemd      ML training + prediction (needs local equivalent)  │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │  install.sh / update.sh [NOT YET WRITTEN]                               │ │
│  │  Applies schema init waves, pulls models from remote, sets env          │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
```

The client-local mode does not require Supabase, DO Spaces, or any cloud account.
All data lives in the local PostgreSQL instance. All ML artifacts live on the local
filesystem. The same FastAPI backend binary serves both modes.

---

## 5. Component-by-Component Comparison

| Component | Shared logic | Dev-cloud implementation | Client-local implementation | Already solved | Still missing | Blocker level |
|-----------|-------------|--------------------------|----------------------------|----------------|---------------|--------------|
| **backend** | `apps/backend/` FastAPI app, all routes, SQLAlchemy | Docker `gb_v2_backend :8002`; volume from `/opt/greenbrain-v2/backend/` (legacy path) | Same Docker image; `client-runtime/docker/docker-compose.yml` | API code complete; portable (no Supabase SDK) | Production `Dockerfile`; compose still mounts legacy path | medium |
| **frontend** | `apps/frontend/` React source, all data hooks use `apiClient.ts` | Docker `gb_v2_frontend :8083`; **Vite dev server** (not production build); volume from `/opt/greenbrain/frontend/` | Docker with production Vite build + nginx (not yet built) | All data hooks already on FastAPI | Production `Dockerfile`; auth replacement; `.env` missing in monorepo copy | **high** |
| **auth** | none yet (`integrations/supabase/client.ts` is cloud-only) | Supabase JS auth (`VITE_SUPABASE_URL` + JWT in browser) | FastAPI JWT (`POST /api/v1/auth/login`, `GET /api/v1/auth/me`) — **not yet implemented** | Cloud dependency map defined in `02-client-runtime-design.md` | FastAPI JWT endpoints; `useAuth.tsx` replacement; `useGardenCenterSettings` FastAPI endpoint | **critical** |
| **postgres** | PostgreSQL 17 schema (DDL identical) | Docker `gb_v2_postgres :5433`; schema from manual `current-schema.sql` snapshot; NOT populated by ETL | Docker `gb_v2_postgres`; schema from `client-runtime/sql/init/` wave files (12 applied) | 12 init waves applied; `_runtime_bootstrap` marker; ~38/58 endpoints at HTTP 200 | ETL to populate tables; ml_ops schema (Wave 7B.3); schema drift between Supabase and local Docker undetected | medium |
| **sql migrations** | Same DDL SQL objects | Supabase cloud (live, manual apply, no runner); 8 migration files misplaced in `jobs/migrations/` | `client-runtime/sql/init/` sequential wave files applied at first DB start | Wave approach validated; idempotent init files work | `sql/` directory empty; no migration runner for future changes; ETL functions not extracted; pg_cron canonical file missing | medium |
| **analytics** | `apps/backend/app/api/v1/analytics.py` router; 16 series views; 12 breakdown views; 7 RPCs | Supabase PostgreSQL with populated `t_core_analytics__*` tables; ETL runs via pg_cron nightly; **REAL/BUSINESS-VALIDATED** (see §6) | Schema stubs present (Wave 7B.1 + 7B.2); endpoints return HTTP 200 empty; **data never populated** (ETL absent) | Series tables + `*_lc` views (Wave 7B.1); breakdown tables/views (Wave 7B.2); RPCs partially applied | ETL SQL functions not in client-runtime; tables always empty without ETL; pg_trgm extension for catalog RPCs | **high** |
| **dashboard** | `apps/backend/app/api/v1/dashboard.py` router; 4 aggregation tables; 3 views; `dashboard__kpis_v2()` | Supabase PostgreSQL populated; `dashboard/reorder-suggestions` **REAL/BUSINESS-VALIDATED**; `dashboard/kpis` **STUB** (accepted) | `t_dashboard_sales_*` stubs + views (Wave 7B.1) → `/dashboard/sales-*` HTTP 200 empty ✅; `kpis` + `reorder-suggestions` status depends on Wave 7B.2 waves | Table stubs + sales views ✅; reorder-suggestions schema from Wave 7B.2 | ETL to populate; `dashboard__kpis_v2()` complex function; `dashboard__reorder_suggestions_top` join tables | medium |
| **planner** | `apps/backend/app/api/v1/planner.py` router; 9 tables; 8 RPCs | Supabase PostgreSQL; `nightly_roll4_tick()` via pg_cron 01:05+12:00 UTC; `/planner/current-week` **STUB**; others functional | `/planner/calendar-events` HTTP 200 empty (tolerant) ✅; `/planner/current-week` pure date-math RPC (Wave 7B.2) ✅; all other planner endpoints 500 | Tolerant calendar-events ✅; current-week stub accepted ✅ | 8 planner RPCs; `nightly_roll4_tick()` scheduler; planner tables populated by ML forecast (which requires full ML pipeline first) | **high** |
| **ops** | `apps/backend/app/api/v1/ops.py` router; `/ops/health` tolerant | `ml_ops` schema fully present; written by ML jobs every run; `/ops/pipeline-status` **STUB** (accepted) | `/ops/health` → `degraded` (not 500, tolerant) ✅; `/ops/pipeline-status` + `/ops/family-runs` → 500 (`ml_ops` schema absent) | Tolerant `/ops/health` ✅; `ml_ops` design complete | `ml_ops` schema not in client init files (Wave 7B.3 planned, not applied); ML jobs not writing to local `ml_ops` | low (simple DDL) |
| **ml training** | `apps/ml-worker/` Python source, model architectures, training logic | systemd `gh-train-biweekly-all` + `gh-train-quarterly`; runs from `/opt/greenhouse/repo/` (legacy); writes to Supabase `ml_forecast` + DO Spaces | **Not portable yet** — hardcoded paths + storage; no local scheduler | Storage abstraction module complete (`apps/ml-worker/storage/`); `gh-refresh-registry` from monorepo (proof of pattern) | Storage wiring (.bak files not applied); shell scripts redirect to legacy; `EnvironmentFile` on legacy; no client scheduler | **critical** |
| **ml prediction** | `apps/ml-worker/` Python source, inference pipeline | systemd `gh-predict-all` nightly 01:30; reads from DO Spaces (models); writes to Supabase `greenhouse_forecast_results_v2` | **Not portable yet** — same blockers as training | Same: storage module written | Same: 4 files still use direct SDK; shell scripts still redirect to legacy | **critical** |
| **storage** | `apps/ml-worker/storage/backend.py` factory (`STORAGE_BACKEND` env var) | `STORAGE_BACKEND=supabase` + `STORAGE_BACKEND=s3` (hardcoded direct SDK calls, NOT using factory yet) | `STORAGE_BACKEND=local` → `LocalStorageBackend` → `LOCAL_STORAGE_ROOT/` | `LocalStorageBackend`, `S3StorageBackend`, `SupabaseStorageBackend` all written | 4 calling files still use Supabase SDK directly; `.bak_phase2b/2c` not applied; `spaces_io.py` not replaced | **critical** |
| **scheduler** | None — different mechanisms per mode | systemd timers (ML) + Supabase pg_cron (ETL + planner) | No scheduler yet. pg_cron can run in local PostgreSQL Docker if extension enabled. systemd equivalent needed for ML | pg_cron can be enabled in client Docker PostgreSQL with `CREATE EXTENSION pg_cron` | No scheduler design for client-local; no ML timer equivalent; pg_cron jobs not versioned in `sql/cron/` | **high** |
| **env variables** | Variable names (mostly); `load_env.sh` mechanism | 4 parallel env systems: `infra/env/dev.env` (4 services), `/opt/greenhouse/.env` (2 services), Docker `.env`, frontend `.env` | `infra/env/client.env` template (exists); `STORAGE_BACKEND=local`, `PG_HOST=localhost`; no Supabase vars | `client.env` template; `load_env.sh` mechanism; `STORAGE_BACKEND` var defined | `SUPABASE_DB_*` aliases missing in `dev.env`; 2 services on legacy env; credentials in source tree | **high** |
| **install / update** | Docker + PostgreSQL + Python runtime assumptions | Manual: `docker-compose up`; `systemctl daemon-reload`; no install script | `install.sh` not written; `update.sh` not written; production Dockerfiles missing | `client-runtime/docker/docker-compose.yml` exists | `install.sh`; `update.sh`; production Dockerfiles for backend + frontend; model pull mechanism | medium |
| **backups / restores** | None designed | Supabase cloud backups (automatic); DO Spaces durability; local Docker DB **not backed up** | No backup mechanism designed for client PostgreSQL or ML artifacts | Nothing | `pg_dump` cron for client DB; ML artifact backup strategy; restore runbook | low |
| **monitoring / logging** | `ops.py` API; `ml_ops` schema tables | `journalctl` for systemd ML jobs; `/ops/pipeline-status` **STUB** (accepted); `ml_ops` tables written by ML jobs | `/ops/health` → `degraded` (tolerant) ✅; pipeline-status/family-runs → 500; no log aggregation; no alerting | Tolerant `/ops/health` ✅; `ml_ops` schema designed | `ml_ops` schema on client (Wave 7B.3); ML jobs writing ops logs to local DB; alerting not designed | low |

---

## 6. Analytics Status

### 6.1 Validated in dev-cloud (REAL with populated data)

These endpoints have been explicitly validated against real data as of Wave 7B.2-K/L:

| Endpoint | Status | Validation note |
|----------|--------|-----------------|
| `GET /api/v1/analytics/series-breakdown` | **REAL / BUSINESS-VALIDATED** | Deterministic non-empty validation for famiglia / categoria / fascia across day-week-month-year |
| `GET /api/v1/analytics/future-windows-stats` | **REAL / BUSINESS-VALIDATED** | Non-empty historical seasonal validation completed |
| `GET /api/v1/analytics/compare-series` | **REAL / SEMANTICALLY-ACCEPTED** | Per-fascia multi-row output per date accepted as correct contract for current phase |
| `GET /api/v1/analytics/entity-summary` | **REAL / STRUCTURE-VALIDATED** | Tree-only hierarchical navigation; quantitative totals explicitly deferred |
| `GET /api/v1/dashboard/reorder-suggestions` | **REAL / BUSINESS-VALIDATED** | Edge cases validated: high/low stock × high/low forecast × multi-family |
| `GET /health`, `/health/db`, `/system/db-info` | **REAL** | Infrastructure always-on |
| `GET /api/v1/catalog/*` | **PARTIAL** | Usable; enrichment deferred |

### 6.2 Validated in client-runtime (HTTP 200, schema present, data empty)

These endpoints return HTTP 200 with correct empty-array structure in client-local mode.
Schema stubs are in place. Data is absent because ETL does not run on client yet.

| Endpoint group | Wave | Schema objects |
|----------------|------|---------------|
| `/api/v1/analytics/series` (all 4 granularities × 4 entity types) | 7B.1 | 16 `t_core_analytics__series_*` tables + 16 `*_lc` views |
| `/api/v1/analytics/series-bounds` | 7B.1 | Same 16 views |
| `/api/v1/analytics/seasonality` | 7B.1 | `t_core_analytics__seasonality_month` + view |
| `/api/v1/analytics/future-windows` | 7B.1 | `greenhouse_forecast_results_v2` stub |
| `/api/v1/forecast/summary`, `/forecast/series`, `/forecast/sample` | 7B.1 | `greenhouse_forecast_results_v2` stub |
| `/api/v1/sales/summary` | 7B.1 | `core_analytics__series_daily_famiglia_lc` view |
| `/api/v1/dashboard/sales-weekly`, `/sales-monthly`, `/sales-yearly` | 7B.1 | 3 `t_dashboard_sales_*` tables + views |
| `/api/v1/catalog/families` | 7B.1 | `famiglie_catalog_static` table |
| `/api/v1/planner/calendar-events` | 7A | Tolerant (ProgrammingError caught) |
| `/health`, `/health/db`, `/system/info`, `/system/db-info` | 7A | No schema needed |

### 6.3 Real but partial in client-runtime (Wave 7B.2 applied, coverage not fully verified)

These objects were targeted by Wave 7B.2A-J but exact per-endpoint HTTP status has not been
re-verified after all 10 sub-waves were applied:

| Endpoint | Target wave | Object type | Uncertainty |
|----------|-------------|-------------|-------------|
| `/api/v1/analytics/series-breakdown` | 7B.2 | 12+ breakdown tables + 12 views | Coverage across all granularities × entity types unconfirmed |
| `/api/v1/analytics/range-totals` | 7B.2-B | `core_analytics__range_totals_v2()` RPC | May be applied; smoke test needed |
| `/api/v1/analytics/stock-and-reorder` | 7B.2-B | `core_analytics__stock_and_reorder_v1()` RPC | Same |
| `/api/v1/catalog/search`, `/catalog/children`, `/catalog/list` | 7B.2-A | 3 catalog RPCs | Applied per 7B.2-A plan; `pg_trgm` extension required |
| `/api/v1/analytics/future-windows-stats` | 7B.2 | `core_analytics__future_window_stats_v2()` RPC | Status after wave application unconfirmed |
| `/api/v1/analytics/compare-series` | 7B.2 | `core_analytics__series_daily_total` join view | Status unconfirmed |
| `/api/v1/analytics/entity-summary` | 7B.2 | `core_analytics__entity_hierarchy_tree_v1()` JSONB RPC | Status unconfirmed |
| `/api/v1/dashboard/reorder-suggestions` | 7B.2-C | `dashboard__reorder_suggestions_top` join view | Applied per 7B.2-C plan |
| `/api/v1/dashboard/kpis` | 7B.2 | `dashboard__kpis_v2()` function | **STUB accepted** for current phase |
| `/api/v1/planner/current-week` | 7B.2 | `core_planner__get_current_week52()` pure date RPC | **STUB accepted** for current phase |

### 6.4 Explicitly deferred from client-runtime

These objects are intentionally absent from all current wave files. They will require
dedicated future waves.

| Object group | Reason for deferral | Required for |
|---|---|---|
| ETL plpgsql functions (`run_greenhouse_daily_pipeline_full`, 5 sub-functions) | Most complex porting task; requires local scheduler equivalent | Tables ever being populated on client |
| ETL `etl` schema (`t_etl_runs`, gate logic) | Tied to ETL functions | `check_etl_ready.sh` gate |
| Planner RPCs (`core_planner__get_*` ×8, `rpc_heatmap_week_pivot`) | Require ML forecast data (`greenhouse_forecast_results_v2` populated) | Planner functionality on client |
| `ml_ops` schema (2 tables + 3 views) | Not yet in any init file — Wave 7B.3 is next planned | `/ops/pipeline-status`, `/ops/family-runs` |
| `ml_forecast` schema (`family_model_registry_v2`) | ML pipeline not portable yet | ML routing on client |
| `mv_core_analytics__*` materialized views | Not in API query path; refresh-pipeline artifact | Never needed for API |
| Supabase-specific schemas (`auth.*`, `storage.*`, `realtime.*`, `vault.*`) | Cloud-only; no client equivalent | Never needed for client |
| pg_cron refresh jobs (10 correct jobs) | pg_cron not yet enabled in client Docker | ETL + planner scheduling |

---

## 7. Architectural Blockers

Ordered by what blocks what else.

| # | Blocker | Mode blocked | Unblocked by |
|---|---------|-------------|-------------|
| **B1** | **Storage abstraction not wired** — 4 ML files still call Supabase SDK directly; `.bak_phase2b/2c` not applied | client-local ML entirely | Apply `.bak_phase2b_fix` → `data_access_v1.py`; apply remaining 3 `.bak` files |
| **B2** | **Frontend auth uses Supabase JS** — `integrations/supabase/client.ts` cannot be removed | client-local login; production frontend image | Implement `POST /api/v1/auth/login` + `GET /api/v1/auth/me` in FastAPI; replace `useAuth.tsx` + `useGardenCenterSettings` |
| **B3** | **ETL SQL functions not in client-runtime** — `run_greenhouse_daily_pipeline_full` and 5 sub-functions absent | analytics and dashboard data ever being populated on client | Extract ETL DDL from Supabase; port as Wave 7B.4; design local scheduler |
| **B4** | **ML shell scripts redirect to legacy repo** — `cd /opt/greenhouse/repo` in all 3 ExecStart scripts | ML monorepo becoming SoT; storage abstraction having any production effect | Fix `GH_REPO_DIR` in `dev.env`; replace `cd /opt/greenhouse/repo` with `cd $GH_REPO_DIR` |
| **B5** | **No production Dockerfiles** — neither `apps/backend/Dockerfile` nor `apps/frontend/Dockerfile` exist | portable Docker images; client install; cloud production build | Write `apps/backend/Dockerfile`; write `apps/frontend/Dockerfile` (build + nginx) |
| **B6** | **No scheduler design for client-local** — pg_cron in Docker PostgreSQL is possible but not set up; no ML timer equivalent | ETL running on schedule on client; planner staying current | Add `pg_cron` extension to client Docker compose; design ML cron or systemd equivalent |
| **B7** | **`sql/` directory empty** — no migration runner, no versioned schema, no pg_cron canonical file | reproducible client install; future schema changes tracked | Export Supabase schema; move 8 migration files; write `sql/migrate.sh` |
| **B8** | **`install.sh` not written** | client product deliverable | All above plus production Dockerfiles and full schema wave coverage |
| **B9** | **pg_cron jobs #30/38/39 — every-minute duplicates** | Supabase DB stability | `SELECT cron.unschedule(30); cron.unschedule(38); cron.unschedule(39);` — 5 minutes, no deployment |
| **B10** | **Credentials in source tree** (`lovabel .env corretto.json`, `env-live.txt`) | Security; must be addressed before any public repo exposure | Delete + rotate Supabase JWT + DO Spaces secret |

---

## 8. Recommended Target Shape

### Backend
Single production Dockerfile in `apps/backend/`. Both modes run the same image.
`POSTGRES_*` env vars point to the appropriate PostgreSQL instance. No mode-specific
code. Auth endpoints added for client-local (also available in dev-cloud).

### Frontend
Single production Dockerfile in `apps/frontend/` (Vite build + nginx). Both modes
serve the same build artifact. Auth is handled by FastAPI JWT, not Supabase JS.
`VITE_API_BASE_URL` is the only mode-specific var.

### PostgreSQL
Both modes run PostgreSQL 17 in Docker. Dev-cloud uses `gb_v2_postgres` populated
by manual snapshot + ETL. Client-local uses the same image, schema loaded from
`client-runtime/sql/init/` waves at first start, populated by local ETL scheduler.
pg_cron extension enabled in both instances.

### Schema management
`sql/migrations/` holds versioned, idempotent DDL files. `sql/migrate.sh` applies
them in order. `sql/cron/pg_cron_canonical.sql` holds the 10 correct job definitions.
`client-runtime/sql/init/` continues as the bootstrap sequence for client install.

### ML pipeline
`apps/ml-worker/` is the sole source. `STORAGE_BACKEND` env var selects backend.
Dev-cloud: `supabase` + `s3`. Client-local: `local`. Same Python code, same model
logic. systemd timers on both sides (parametrized, not hardcoded to `/opt/greenhouse`).

### Scheduler
Both modes use pg_cron (extension in Docker PostgreSQL) for ETL + planner refresh.
Both modes use systemd timers (or equivalent) for ML training + prediction. The job
definitions are identical SQL; only connection strings differ.

### Auth
FastAPI JWT auth (`apps/backend/app/api/v1/auth.py` — to be created). Frontend
replaces `integrations/supabase/client.ts` with `apiClient.ts` calls. Same auth
logic in both modes.

### Install
`client-runtime/install.sh` (to be written):
1. `docker-compose up -d` (postgres + backend + frontend)
2. Wait for postgres; run `sql/init/` wave files in order
3. Set `pg_cron` extension; load `sql/cron/pg_cron_canonical.sql` (client variant)
4. Populate `infra/env/client.env` from template
5. Pull initial model bundles from remote or local media

---

## 9. Immediate Next Implementation Sequence

**This week — zero-risk, no deployment downtime:**

| Step | Action | Time | Unlocks |
|------|--------|------|---------|
| 1 | Disable pg_cron #30/38/39 on Supabase | 5 min | Supabase DB stability |
| 2 | Delete `lovabel .env corretto.json` + `env-live.txt`; rotate Supabase JWT + DO Spaces key | 30 min | Security |
| 3 | Add `SUPABASE_DB_*=${PG_*}` aliases to `infra/env/dev.env` | 10 min | Unblocks `export_features_dense.py` in monorepo |
| 4 | Apply `ml_ops` schema as Wave 7B.3 (2 tables + 3 views) | 30 min | `/ops/pipeline-status` + `/ops/family-runs` → 200 |
| 5 | Apply `.bak_phase2b_fix` → `apps/ml-worker/data_access_v1.py`; smoke with `STORAGE_BACKEND=supabase` + `PREDICT_LIMIT=1` | 1 hr | First storage abstraction validation |

**Next — storage abstraction completion (requires step 5 to pass first):**

| Step | Action | Unlocks |
|------|--------|---------|
| 6 | Apply `.bak_phase2b` → `export_features_dense.py`; apply `.bak_phase2c` → priors scripts | Full storage wiring |
| 7 | Fix ML shell scripts: replace `cd /opt/greenhouse/repo` with `cd $GH_REPO_DIR` | ML runs from monorepo |
| 8 | Migrate `gh-train-biweekly` + `gh-train-quarterly` to `load_env.sh` | Legacy env eliminated |
| 9 | Write `apps/backend/Dockerfile` + update docker-compose volume to `apps/backend/` | Production backend image |

**Then — auth + frontend (requires step 9):**

| Step | Action | Unlocks |
|------|--------|---------|
| 10 | Implement `POST /api/v1/auth/login` + `GET /api/v1/auth/me` in FastAPI | client-local login |
| 11 | Replace `src/integrations/supabase/client.ts` with FastAPI JWT hooks | Frontend Supabase dependency removed |
| 12 | Write `apps/frontend/Dockerfile` (Vite build + nginx) | Production frontend image |

**Then — client-local completeness:**

| Step | Action | Unlocks |
|------|--------|---------|
| 13 | Port ETL SQL functions to client-runtime as Wave 7B.4 | Data ever being populated on client |
| 14 | Enable `pg_cron` in client Docker PostgreSQL; load ETL schedule | Automatic data refresh on client |
| 15 | Write `client-runtime/install.sh` | Client product deliverable |

---

*Cross-reference: `docs/architecture/02-client-runtime-design.md` · `docs/architecture/separation-boundary.md` · `docs/architecture/runtime-current-state.md` · `docs/migration/source-of-truth.md` · `docs/migration/migration-map.md`*
