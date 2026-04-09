# GreenBrain — Canonical Source-of-Truth
> Supersedes earlier draft (2026-03-27). Evidence-based only. No invented facts.
> Updated: 2026-04-01. Sources: full-system-inventory-01/02/03, apps/, infra/, client-runtime/, direct inspection.
>
> Two execution modes:
> - **dev-cloud** — cloud droplet, Docker + systemd, Supabase + DO Spaces
> - **client-local** — garden-center server, Docker only, local PostgreSQL + local storage

---

## How to read the domain tables

Each domain has a vertical key→value table. Status values: **real** = running in production · **partial** = partially migrated · **legacy** = old code still active · **stub** = schema created but empty · **blocked** = cannot proceed without prerequisite.

---

## 1. BACKEND

| Property | Value |
|----------|-------|
| **Current real SoT** | `/opt/greenbrain-v2/backend/` — Docker volume mount for `gb_v2_backend` |
| **Competing copies** | `apps/backend/` — identical Python source, not mounted by any container |
| **Target SoT** | `apps/backend/` |
| **Execution location** | Docker `gb_v2_backend` :8002 · uvicorn · reads `gb_v2_postgres:5433` (local Docker DB, NOT Supabase) |
| **Status** | **real** (running) · monorepo copy **partial** (idle, `.bak` artifacts present) |
| **Portability to client-local** | ✅ HIGH — all DB calls use `POSTGRES_*` env vars via SQLAlchemy; zero Supabase SDK usage |
| **Main blockers** | Docker compose mounts `greenbrain-v2/backend`, not monorepo; production `Dockerfile` missing; `.bak` files in `apps/backend/` |
| **Next action** | Write `apps/backend/Dockerfile` (uvicorn production); update docker-compose volume to `apps/backend`; delete `app/core/config.py.bak` + `app/api/v1/ops.py.bak` |

---

## 2. FRONTEND

| Property | Value |
|----------|-------|
| **Current real SoT** | `/opt/greenbrain/frontend/` — Docker volume mount for `gb_v2_frontend` |
| **Competing copies** | `apps/frontend/` — identical `src/`, missing `.env` and `supabase/`, not Docker-mounted |
| **Target SoT** | `apps/frontend/` |
| **Execution location** | Docker `gb_v2_frontend` :8083 — **Vite dev server** (`npm run dev`), not a production build |
| **Status** | **real** (running) · **legacy** mode (dev server) · monorepo copy **blocked** (no `.env`, no `supabase/`) |
| **Portability to client-local** | ❌ BLOCKED — auth via Supabase JS (`integrations/supabase/client.ts`); `useGardenCenterSettings` hook calls `supabase.from()` directly |
| **Main blockers** | (1) Supabase auth not replaced with FastAPI JWT; (2) `.env` missing from monorepo copy; (3) production `Dockerfile` missing; (4) 3 conflicting lock files (`bun.lock` + `bun.lockb` + `package-lock.json`) |
| **Next action** | Replace Supabase auth with FastAPI JWT; copy `.env` → `apps/frontend/`; resolve lock file conflict; write `Dockerfile` (build + nginx); update Docker compose mount |

---

## 3. ML (training + inference)

| Property | Value |
|----------|-------|
| **Current real SoT** | `/opt/greenhouse/repo/` — 5 of 6 systemd ML timers execute Python from here |
| **Competing copies** | `apps/ml-worker/` — partially migrated: `.bak_phase2b/2c` files = migrated versions of 4 storage-calling files (not applied); `refresh_registry.py` is the single exception (runs from monorepo) |
| **Target SoT** | `apps/ml-worker/` |
| **Execution location** | Systemd host: `gh-parquet-export` 21:35 · `gh-train-missing` 01:10 · `gh-predict-all` 01:30 · `gh-train-biweekly-all` biweekly · `gh-train-quarterly` quarterly — all 5 execute from `/opt/greenhouse/repo/` |
| **Status** | **real** (from legacy repo) · **partial** migration (storage abstraction written, not wired; shell scripts redirect to legacy path) |
| **Portability to client-local** | ❌ BLOCKED — hardcoded `/opt/greenhouse/` paths; Supabase Storage + DO Spaces hardcoded; venv at `/opt/greenhouse/venv/`; no portable scheduler |
| **Main blockers** | (1) 4 files (`data_access_v1.py`, `export_features_dense.py`, priors scripts) still call Supabase SDK directly; (2) shell scripts contain `cd /opt/greenhouse/repo`; (3) `gh-train-biweekly/quarterly` use `EnvironmentFile=/opt/greenhouse/.env`; (4) `export_features_dense.py` uses `SUPABASE_DB_*` naming not in `dev.env` |
| **Next action** | Apply `.bak_phase2b_fix` → `data_access_v1.py`; apply remaining `.bak` files to 3 other files; fix shell script paths to use `GH_REPO_DIR`; migrate biweekly/quarterly to `load_env.sh` |

---

## 4. SQL / SCHEMA / MIGRATIONS

| Property | Value |
|----------|-------|
| **Current real SoT** | Supabase PostgreSQL (live cloud DB) — all schema changes applied manually, no migration runner |
| **Competing copies** | `greenbrain-v2/database/current-schema.sql` — snapshot from **local Docker DB** (not Supabase), drift undetected; 8 `blocco_*_migration.sql` files in `jobs/migrations/` (wrong directory, identical in both repos) |
| **Target SoT** | `sql/schema/` + `sql/migrations/` + `sql/cron/` — all **currently empty** in monorepo |
| **Execution location** | Supabase cloud (live); local Docker `gb_v2_postgres:17` (snapshot, read by FastAPI backend) |
| **Status** | **legacy** — no version control, no migration runner, no idempotency, manual apply only |
| **Portability to client-local** | ❌ BLOCKED — ETL plpgsql functions (`run_greenhouse_daily_pipeline_full`, `refresh_forecast_features_dense_range`, etc.) never extracted; `sql/` directory empty |
| **Main blockers** | `sql/` directory empty; 8 migration files misplaced in `jobs/migrations/`; no Alembic/Flyway; snapshot may not match live Supabase; ETL functions not extracted anywhere |
| **Next action** | Export Supabase schema (`pg_dump --schema-only`); move 8 files → `sql/migrations/` with sequential prefix; write `sql/cron/pg_cron_canonical.sql` with 10 correct jobs (excluding #30/38/39) |

---

## 5. ANALYTICS

| Property | Value |
|----------|-------|
| **Current real SoT** | Supabase PostgreSQL: 48+ pre-aggregated tables — series ×16 (`t_core_analytics__series_{daily,weekly,monthly,yearly}_{famiglia,categoria,fascia,fascia_prezzo}`), breakdown ×12+ (`t_core_analytics__breakdown_{gran}_{entity}_fp_v2`), `t_core_analytics__seasonality_month`; 6 matviews `mv_core_analytics__*`; 7 RPCs (`core_analytics__range_totals_v2`, `entity_hierarchy_tree_v1`, `stock_and_reorder_v1`, `future_window_stats_v2`, `search_catalog_rich`, `catalog_children`, `list_catalog`) |
| **Competing copies** | client-runtime `02_schema_7b1.sql`: 16 series tables (stubs) + 16 `*_lc` views ✅; breakdown tables/views via Wave 7B.2 sub-waves (exact coverage TBD); matviews **excluded** (not in API query path) |
| **Target SoT** | client-runtime `sql/init/` files |
| **Execution location** | Backend `analytics.py` router · `/analytics/series`, `/analytics/series-breakdown`, `/analytics/compare-series`, `/analytics/seasonality`, `/analytics/entity-summary`, `/analytics/range-totals`, `/analytics/future-windows-stats`, `/analytics/stock-and-reorder`, `/analytics/components`; **populated by ETL pg_cron** via `refresh_core_analytics_range()` |
| **Status** | **real** (Supabase) · **stub** in client-runtime (series tables + views present → `/analytics/series` 200 empty; complex RPCs partially applied via 7B.2; ~38/58 total endpoints across all domains at 200) |
| **Portability to client-local** | ⚠️ PARTIAL — table/view stubs portable; complex RPCs need `pg_trgm` extension; **ETL not in client-runtime → tables always empty** |
| **Main blockers** | `refresh_core_analytics_range()` ETL function not in client-runtime; exact Tier 3/4 RPC coverage after Wave 7B.2 not verified without reading each wave file |
| **Next action** | Verify which analytics endpoints are still 500 after Wave 7B.2J; port ETL analytics refresh function to client-runtime; add `pg_trgm` extension to bootstrap |

---

## 6. DASHBOARD

| Property | Value |
|----------|-------|
| **Current real SoT** | Supabase PostgreSQL: `t_dashboard_sales_{daily,weekly,monthly,yearly}` (4 tables); views `dashboard__sales_{weekly,monthly,yearly}` + `dashboard__reorder_suggestions_top`; function `dashboard__kpis_v2()` |
| **Competing copies** | client-runtime `02_schema_7b1.sql`: 4 dashboard table stubs + 3 `dashboard__sales_*` views ✅; `dashboard__kpis_v2()` and `dashboard__reorder_suggestions_top` status depends on 7B.2 waves |
| **Target SoT** | client-runtime `sql/init/` files |
| **Execution location** | Backend `dashboard.py` router · `/dashboard/sales-weekly`, `/dashboard/sales-monthly`, `/dashboard/sales-yearly`, `/dashboard/kpis`, `/dashboard/reorder-suggestions`; **populated by ETL** via `refresh_dashboard_sales_range()` |
| **Status** | **real** (Supabase) · **stub** in client-runtime (`/dashboard/sales-*` → 200 empty ✅; `/dashboard/kpis` and `/dashboard/reorder-suggestions` status uncertain after 7B.2) |
| **Portability to client-local** | ⚠️ PARTIAL — tables/views portable; `dashboard__kpis_v2()` multi-table aggregation; `dashboard__reorder_suggestions_top` joins `greenhouse_products_normalized` + `greenhouse_stock_raw_upload` (presence in client schema unconfirmed) |
| **Main blockers** | `dashboard__kpis_v2()` complexity; `dashboard__reorder_suggestions_top` join-table dependencies; ETL not in client-runtime → data never populated |
| **Next action** | Confirm `/dashboard/kpis` HTTP status; if still 500 apply missing function; port ETL dashboard refresh function |

---

## 7. PLANNER

| Property | Value |
|----------|-------|
| **Current real SoT** | Supabase PostgreSQL: 9 tables (`t_core_planner__{assortment_calendar,heat_cells,space_budget,fact_weekly,params_level,potsize_profile,density,orchestrator_state,refresh_state}`) + `t_forecast_fam_daily`; view `greenhouse_order_suggestions_enriched_v2`; 8 RPCs (`core_planner__get_{space_budget,assortment_calendar,heatmap_nodes,heatmap_week_ranges,heatmap_roll4_ranges,heatmap_cells,current_week52}` + `rpc_heatmap_week_pivot`) |
| **Competing copies** | client-runtime: planner tables partially applied via 7B.2 waves (exact coverage unknown); `/planner/calendar-events` is tolerant → 200 empty; all other planner endpoints 500 if RPCs missing |
| **Target SoT** | client-runtime `sql/init/` files + local scheduler for `nightly_roll4_tick()` |
| **Execution location** | Backend `planner.py` router · 8+ endpoints; **populated by pg_cron** `core_planner__nightly_roll4_tick(2)` at 01:05+12:00 UTC, reading `greenhouse_forecast_results_v2` |
| **Status** | **real** (Supabase) · **blocked** in client-runtime (complex plpgsql RPCs; depends on ML forecast output) |
| **Portability to client-local** | ❌ LOW — 8 complex plpgsql RPCs; populated only from ML forecast results (which requires full ML pipeline first); pg_cron not portable |
| **Main blockers** | (1) 8 planner RPCs not yet confirmed in client-runtime; (2) planner tables populated by `nightly_roll4_tick()` which needs `greenhouse_forecast_results_v2` — requires ML pipeline first; (3) no local scheduler for roll4 tick |
| **Next action** | Defer until ML pipeline portable; then port planner RPCs; write cron-based scheduler equivalent for `nightly_roll4_tick()` |

---

## 8. OPS

| Property | Value |
|----------|-------|
| **Current real SoT** | Supabase PostgreSQL: `ml_ops.pipeline_run_log_v1`, `ml_ops.family_run_log_v1`, `t_ops_pipeline_monitor`; views `ml_ops.v_pipeline_runs_recent_v1`, `ml_ops.v_daily_pipeline_summary_v1`, `public.v_ops_pipeline_status`; written by ML systemd jobs on every train/predict run |
| **Competing copies** | None — `ml_ops` schema not yet in any client-runtime init file |
| **Target SoT** | client-runtime `sql/init/` files |
| **Execution location** | Backend `ops.py` router · `/ops/health` (tolerant: returns `degraded` on missing schema, not 500) · `/ops/pipeline-status` (500 without `ml_ops`) · `/ops/family-runs` (500 without `ml_ops`) |
| **Status** | **real** (Supabase) · **blocked** in client-runtime (`ml_ops` schema absent → 2 of 3 ops endpoints 500) |
| **Portability to client-local** | ⚠️ MEDIUM — schema is simple (2 tables + 3 views + 1 public view); portable once ML jobs write to local DB |
| **Main blockers** | `ml_ops` schema not in client-runtime init files; ML jobs not yet portable (won't write to `ml_ops` on client until ML pipeline migrated) |
| **Next action** | Apply `ml_ops` schema as Wave 7B.3 (2 tables + 3 views) → unblocks `/ops/pipeline-status` and `/ops/family-runs` (will return 200 empty) |

---

## 9. ENV / CONFIG

| Property | Value |
|----------|-------|
| **Current real SoT** | **4 parallel systems**: (1) `/opt/greenhouse/.env` — 2 systemd services via `EnvironmentFile=`; (2) `infra/env/base.env + dev.env` via `load_env.sh` — 4 systemd services; (3) `/opt/greenbrain-v2/deploy/.env` — Docker stack `gb_v2_*`; (4) `/opt/greenbrain/frontend/.env` — Vite build |
| **Competing copies** | Systems 1 and 2 define the same ML/storage vars with same values but different naming: `SUPABASE_DB_*` only in system 1; `STORAGE_BACKEND` + `LOCAL_STORAGE_ROOT` only in system 2; `SUPABASE_KEY` legacy alias only in system 1; **live credentials in source tree**: `apps/ml-worker/ISTRUZIONI*/lovabel .env corretto.json` + `docs/operations/env-live.txt` |
| **Target SoT** | `infra/env/{base,dev,client}.env` via `load_env.sh` as the sole systemd env system; Docker and frontend read from separate but derived templates |
| **Execution location** | systemd `EnvironmentFile` (legacy, 2 services); `source load_env.sh` in `ExecStartPre` (monorepo, 4 services); `docker-compose --env-file` (Docker); Vite build `.env` (frontend) |
| **Status** | **fragile** — 4 parallel systems; 2 services on legacy env; credential leak in source tree |
| **Portability to client-local** | ⚠️ PARTIAL — `infra/env/client.env` template exists; `SUPABASE_DB_*` aliases missing → `export_features_dense.py` crashes when run with `dev.env` only |
| **Main blockers** | (1) **CRITICAL**: credentials in source tree (Supabase JWT + DO Spaces secret in `lovabel .env corretto.json` and `env-live.txt`); (2) `SUPABASE_DB_*` vars absent from `dev.env`; (3) `gh-train-biweekly` and `gh-train-quarterly` still on `/opt/greenhouse/.env` |
| **Next action** | **IMMEDIATE**: delete `lovabel .env corretto.json` from both repos + `env-live.txt`; rotate Supabase JWT + DO Spaces key; add `SUPABASE_DB_HOST=${PG_HOST}` aliases to `dev.env`; migrate biweekly/quarterly to `load_env.sh` |

---

## 10. STORAGE

| Property | Value |
|----------|-------|
| **Current real SoT** | Supabase Storage bucket `ml-snapshots` (parquet features + priors); DO Spaces `greenbrainmodels/models_v4/` (1886+ model `.pkl` bundles); accessed via hardcoded Supabase SDK + `scripts/spaces_io.py` (boto3) in running code |
| **Competing copies** | `apps/ml-worker/storage/` — factory module (`backend.py` + `local_backend.py` + `s3_backend.py` + `supabase_backend.py`); **complete but not wired**; `.bak_phase2b/2c` = migrated versions of 4 calling files (not yet applied to originals) |
| **Target SoT** | `apps/ml-worker/storage/backend.py` factory, selected by `STORAGE_BACKEND=supabase|local|s3` env var |
| **Execution location** | Direct SDK calls in: `data_access_v1.py` (parquet read/cache), `export_features_dense.py` (parquet write), `upload/download_priors_*.py` (priors), `scripts/spaces_io.py` (model bundles) |
| **Status** | **partial** — abstraction module complete; 4 calling files not updated; `.bak` files contain the correct migration |
| **Portability to client-local** | ❌ BLOCKED — without wiring, ML always requires Supabase Storage + DO Spaces; `LocalStorageBackend` exists but unreachable |
| **Main blockers** | `.bak_phase2b/2c` not applied to originals; `spaces_io.py` not replaced by `S3StorageBackend`; `LOCAL_STORAGE_ROOT` not tested end-to-end |
| **Next action** | Apply `.bak_phase2b_fix` → `data_access_v1.py`; apply `.bak_phase2b` → `export_features_dense.py`; apply `.bak_phase2c` → priors scripts; smoke-test `STORAGE_BACKEND=supabase` (no behavior change); then test `STORAGE_BACKEND=local` |

---

## 11. SYSTEMD

| Property | Value |
|----------|-------|
| **Current real SoT** | `/etc/systemd/system/gh-*.service` + `gh-*.timer` (12 unit files; 6 timers enabled in `timers.target.wants/`) |
| **Competing copies** | `infra/systemd/current/` — mirror, in sync at inspection; 9 `.bak*` files in `/etc/systemd/system/` (stale, not loaded by systemd) |
| **Target SoT** | `infra/systemd/` (flatten `current/` subdirectory) + `infra/systemd/install.sh` |
| **Execution location** | Host systemd — 6 active timers: `gh-parquet-export` (21:35), `gh-refresh-registry` (00:45), `gh-train-missing` (01:10), `gh-predict-all` (01:30), `gh-train-biweekly-all` (Sun 1+15 02:00), `gh-train-quarterly` (1 Jan/Apr/Jul/Oct 02:30) |
| **Status** | **real** — units correct and in sync with monorepo mirror; `biweekly` + `quarterly` units still use legacy `EnvironmentFile=/opt/greenhouse/.env` and `WorkingDirectory=/opt/greenhouse/repo` |
| **Portability to client-local** | ❌ NOT PORTABLE — `WorkingDirectory` hardcoded to server paths; no parametrized templates; client installer does not exist |
| **Main blockers** | No parametrized templates for client install; 2 units use legacy `EnvironmentFile` + `WorkingDirectory`; 9 `.bak*` files in `/etc/systemd/system/` |
| **Next action** | Delete 9 `.bak*` files; flatten `infra/systemd/current/` → `infra/systemd/`; write `install.sh`; after ML migration: parametrize `WorkingDirectory` + `EnvironmentFile` in all 6 units |

---

## 12. DOCKER / DEPLOY

| Property | Value |
|----------|-------|
| **Current real SoT** | `/opt/greenbrain-v2/deploy/` — `docker-compose.base.yml` + `docker-compose.dev.yml` + `docker-compose.client.yml` + `.env`; 6 running containers: `gb_v2_backend :8002`, `gb_v2_frontend :8083`, `gb_v2_nginx :8082`, `gb_v2_postgres :5433`, `gb_v2_pgadmin :5050`, `gb_v2_ml` (dead — `sleep infinity`) |
| **Competing copies** | `client-runtime/docker/docker-compose.yml` — client stack (postgres + backend only); separate from cloud stack |
| **Target SoT** | Cloud: `infra/docker/` · Client: `client-runtime/docker/` (already in place) |
| **Execution location** | Cloud: Docker host (all 6 containers up) · Client: Docker host at client site (2-container stack: postgres + backend) |
| **Status** | **real** (cloud stack) · **partial** (client-runtime: DB + backend only; no frontend; no ML; `gb_v2_ml` dead placeholder) |
| **Portability to client-local** | ⚠️ PARTIAL — `client-runtime/docker/docker-compose.yml` exists; production `Dockerfile` for backend missing; production `Dockerfile` for frontend (build + nginx) missing |
| **Main blockers** | (1) Production `Dockerfile` for backend missing; (2) Production `Dockerfile` for frontend (nginx + Vite build) missing; (3) Cloud compose volumes reference non-monorepo paths; (4) `gb_v2_ml` is a dead placeholder with no plan |
| **Next action** | Write `apps/backend/Dockerfile`; write `apps/frontend/Dockerfile`; update cloud compose volumes to monorepo paths; decide: implement or remove `gb_v2_ml` |

---

## 13. CLIENT-RUNTIME

| Property | Value |
|----------|-------|
| **Current real SoT** | `client-runtime/` in monorepo — partially built; not deployed to any real client |
| **Competing copies** | None |
| **Target SoT** | `client-runtime/` (already here) — goal: complete installable package with `install.sh` |
| **Execution location** | Local Docker stack at client site: `client-runtime/docker/docker-compose.yml` — `gb_v2_postgres:17` + backend; no ML, no ETL, no frontend container |
| **Status** | **partial** — 12 SQL init waves applied (Wave 7A + 7B.1 + 7B.2A-J); ~38/58 API endpoints at HTTP 200; ETL/planner/ops schemas missing; auth blocked; ML pipeline not portable; `install.sh` not written |
| **Portability to client-local** | ⚠️ MEDIUM — schema portability in progress wave-by-wave; backend fully portable; frontend + ML blocked |
| **Main blockers** | (1) Frontend auth (Supabase JS) — login impossible without Supabase cloud; (2) ETL SQL functions not in client-runtime → DB never populated from real data; (3) ML pipeline: hardcoded paths + cloud storage; (4) Scheduler: pg_cron not portable; (5) `install.sh` not written; (6) ~20 endpoints still 500 (planner RPCs, ml_ops, some Tier 4 analytics) |
| **Next action** | (a) Apply ml_ops schema as Wave 7B.3 — simple, unblocks 2 endpoints; (b) Verify exact Tier 3/4 endpoint status; (c) Port ETL analytics/dashboard refresh functions; (d) Replace frontend auth with FastAPI JWT |

### Wave progress detail

| Init file | Wave | Objects | Tier covered |
|-----------|------|---------|-------------|
| `01_bootstrap.sql` | 7A | `_runtime_bootstrap` table | Tier 0 (4 endpoints) ✅ |
| `02_schema_7b1.sql` | 7B.1 | 23 tables + 20 views | Tier 2 (27 endpoints) ✅ |
| `03_schema_7b2a.sql` | 7B.2-A | Tier 3 partial | Tier 3 simple RPCs partial |
| `04_schema_7b2b.sql` | 7B.2-B | Tier 3 partial | Tier 3 simple RPCs partial |
| `05–12_schema_7b2c-j.sql` | 7B.2-C through J | Tier 4/5 partial | Tier 4 complex analytics + ml_ops partial |

> ~38/58 endpoints at HTTP 200 after all 12 waves. ~20 still 500: planner RPCs, `ml_ops` schema, some Tier 4 analytics RPCs. Exact per-wave coverage requires reading each wave file — not done.

---

## Appendix A — Top 10 Ambiguities Still Open

1. **Exact docker-compose frontend volume mount.** `docker-compose.base.yml` declares `- ../frontend:/app` which resolves to `/opt/greenbrain-v2/frontend/` (a 4-file stub directory). Yet `gb_v2_frontend` runs the full React app. The actual mounted path — whether `gb_v2_frontend` or `gb_v2_nginx` serves it, or whether the mount is overridden elsewhere — is unresolved.

2. **Exact Tier 3/4/5 endpoint coverage after Wave 7B.2A–J.** ~38/58 endpoints work but per-wave breakdown is unknown without reading each wave file. It is not confirmed which analytics RPCs, planner functions, and ml_ops objects were applied.

3. **Schema drift between Supabase cloud and local Docker `gb_v2_postgres`.** `current-schema.sql` was exported from the local Docker DB, not Supabase. Magnitude of drift is undetected. The FastAPI backend reads from the local DB — if it lacks tables that Supabase has, analytics endpoints return wrong/empty results.

4. **Whether `spaces_io.py` (DO Spaces / boto3) is covered by the storage abstraction plan.** The `.bak_phase2b/2c` files migrate Supabase Storage calls but it is unclear if `ensure_model_bundle.py` and `sync_local_artifacts.py` (using `spaces_io.py`) are also in scope for the `S3StorageBackend` wiring.

5. **`dashboard__reorder_suggestions_top` view dependencies.** It joins `greenhouse_products_normalized` and `greenhouse_stock_raw_upload`. Whether these tables are present in any client-runtime init file is unconfirmed.

6. **`SUPABASE_KEY` legacy alias behavior.** `data_access_v1.py` calls `os.getenv("SUPABASE_KEY")`. This var exists in `/opt/greenhouse/.env` but not in `dev.env`. Whether this causes a crash or a silent `None` return on the monorepo path depends on which code branch is hit.

7. **CLI bin PATH order.** Whether `/opt/greenhouse/bin/` or `infra/scripts/bin/` resolves first in `$PATH` for both interactive and non-interactive shells is not documented. The behavior of manually running `gh-predict-all` is ambiguous and operator-dependent.

8. **`ml_forecast` schema in client-runtime.** The endpoint matrix marks `ml_forecast.*` as "deferred." Whether any Wave 7B.2 sub-wave applied it is unknown. This schema contains `family_model_registry_v2` — needed by the ML worker for model routing.

9. **FastAPI JWT auth design for client-local.** The plan says "replace Supabase auth with FastAPI JWT" but the concrete endpoints (`POST /auth/login`, `GET /auth/me`), token storage strategy, and `useGardenCenterSettings` data endpoint are not yet designed or scoped.

10. **Whether `gb_v2_postgres` local Docker DB contains any real data.** If it is empty, all analytics/dashboard API endpoints return HTTP 200 with empty arrays — correct schema, zero utility. No evidence of data population from any ETL or seed process was found.

---

## Appendix B — Top 10 Decisions Already Solid

1. **ML Python source of truth is `/opt/greenhouse/repo/`** until shell scripts and `WorkingDirectory` are changed. Editing `apps/ml-worker/` has zero effect on production. Do not confuse the two.

2. **Storage abstraction design is correct and complete.** `storage/backend.py` factory + `STORAGE_BACKEND` env var is the right pattern. The `.bak_phase2b/2c` files contain the correct migration. Apply them — do not redesign.

3. **FastAPI backend is fully portable.** `apps/backend/` uses only `POSTGRES_*` env vars via SQLAlchemy. No Supabase SDK. Production `Dockerfile` is the only missing piece.

4. **All frontend data hooks use `apiClient.ts` → FastAPI.** Data portability is complete. Only auth (`integrations/supabase/`) and `useGardenCenterSettings` remain on Supabase. This boundary is correct.

5. **pg_cron jobs #30, #38, #39 must be disabled immediately.** They are confirmed duplicate every-minute triggers. `SELECT cron.unschedule(N)` is safe and reversible. Jobs #11, #29, #37 provide full correct ETL scheduling.

6. **`load_env.sh` is the correct env system.** Four systemd services already use it. Legacy `/opt/greenhouse/.env` is the one to eliminate. Migration direction is unambiguous.

7. **client-runtime Wave approach (7A → 7B.1 → 7B.2-X) is validated.** Empty table stubs → views compile → endpoints return HTTP 200 empty. This is confirmed by ~38/58 working endpoints. Continue the pattern.

8. **Supabase Storage `ml-snapshots` and DO Spaces `greenbrainmodels` are the single truth for parquet and model bundles.** Local caches at `/opt/greenhouse/repo/parquet_cache/` and `models_v4/` are derivatives. Do not treat them as authoritative. They should be gitignored.

9. **`gh-refresh-registry` running from monorepo proves the migration pattern works.** It is proof that a systemd service can run Python from `apps/ml-worker/` with `load_env.sh` and succeed. The same setup applies to all other ML services.

10. **The `etl` schema (`t_etl_runs`) is the gate for parquet export.** `check_etl_ready.sh` queries `etl.t_etl_runs` for a SUCCESS record before parquet export starts. Any client-runtime ETL implementation must write to this table for the export gate to function.

---

## Appendix C — Recommended Next Consolidation Step

**Do these three things in sequence. Each is independent within its own step.**

### Step 1 — Immediate (today, ~1 hour, zero deployment risk)

```sql
-- On Supabase SQL editor: disable duplicate pg_cron jobs
SELECT cron.unschedule(30);
SELECT cron.unschedule(38);
SELECT cron.unschedule(39);
```

```bash
# Delete credential files (then rotate the exposed keys)
rm "/opt/greenhouse/repo/ISTRUZIONI & FUNZIONAMENTO/lovabel .env corretto.json"
rm "/opt/greenbrain-platform/apps/ml-worker/ISTRUZIONI & FUNZIONAMENTO/lovabel .env corretto.json"
rm /opt/greenbrain-platform/docs/operations/env-live.txt
# Then rotate: SUPABASE_SERVICE_ROLE_KEY and DO_SPACES_SECRET in all env files
```

### Step 2 — This week (low-risk, high unlock value)

```bash
# Fix SUPABASE_DB_* alias gap in dev.env (prevents export_features_dense.py crash)
echo 'SUPABASE_DB_HOST=${PG_HOST}' >> /opt/greenbrain-platform/infra/env/dev.env
echo 'SUPABASE_DB_PORT=${PG_PORT}' >> /opt/greenbrain-platform/infra/env/dev.env
echo 'SUPABASE_DB_NAME=${PG_DB}'   >> /opt/greenbrain-platform/infra/env/dev.env
echo 'SUPABASE_DB_USER=${PG_USER}' >> /opt/greenbrain-platform/infra/env/dev.env
echo 'SUPABASE_DB_PASSWORD=${PG_PASSWORD}' >> /opt/greenbrain-platform/infra/env/dev.env
```

Apply `ml_ops` schema as Wave 7B.3 — 2 tables + 3 views. Simple DDL. Unblocks `/ops/pipeline-status` and `/ops/family-runs` to HTTP 200.

### Step 3 — Storage abstraction wiring (highest leverage)

Apply `.bak_phase2b_fix` → `data_access_v1.py` in monorepo only. Test with `STORAGE_BACKEND=supabase` and `PREDICT_LIMIT=1`. No behavior change expected — this validates the wiring before touching any other file.

**Why this is the highest-leverage action:** wiring the storage abstraction to all 4 ML files is the prerequisite for (a) ML monorepo unification, (b) client-local ML, and (c) any multi-cloud deployment. All three major open tracks are blocked by it.

---

*Cross-reference: `docs/analysis-stato-sistema-2026-04.md` for full gap analysis, flaw inventory, and 5-phase roadmap.*
