# GreenBrain — Migration Map
> Current hybrid reality → target architecture (dev-cloud + client-local).
> Updated: 2026-04-01. Evidence-based only.
> SoT = Source of Truth · CR = client-runtime · n/a = not applicable

Column key:
- **action**: keep · copy · replace · archive · delete
- **status**: active-canonical · active-legacy · copied-idle · partial · not-started · blocked · complete
- **risk**: critical · high · medium · low

---

## Table

| current path | target path | category | current role | SoT? | status | action | dev-cloud impact | client-local impact | required tests | risk | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `/opt/greenbrain-v2/backend/` | `apps/backend/` | backend-code | Docker volume mount — running `gb_v2_backend :8002` | ✅ yes | active-legacy | archive (after switch) | Docker restart required | none yet | `GET /health` → 200 after compose update | medium | Code identical to monorepo copy |
| `apps/backend/` | same | backend-code | Monorepo copy — idle, not Docker-mounted | ❌ no | copied-idle | replace (become SoT) | Docker compose volume update | Dockerfile needed | uvicorn starts; `GET /health` → 200 | medium | Has `.bak` artifacts to delete |
| `apps/backend/Dockerfile` | same | backend-deploy | Does not exist | — | not-started | create | enables production image | enables client image | image builds; uvicorn starts | low | `FROM python:3.11-slim` + `COPY` + `CMD uvicorn` |
| `/opt/greenbrain/frontend/` | `apps/frontend/` | frontend-code | Docker volume mount — running `gb_v2_frontend :8083` | ✅ yes | active-legacy | archive (after switch) | Docker restart required | none yet | all frontend routes load after compose update | high | Has `.env` + `supabase/` that must be copied first |
| `apps/frontend/` | same | frontend-code | Monorepo copy — idle, no `.env`, no `supabase/` | ❌ no | copied-idle | replace (become SoT) | Docker compose volume update | auth must be replaced first | `npm run build` succeeds | high | 3 lock files conflict; Supabase auth blocks portability |
| `apps/frontend/Dockerfile` | same | frontend-deploy | Does not exist | — | not-started | create | production build + nginx | client production image | `npm run build` + nginx serves `index.html` | medium | Replace Vite dev server |
| `/opt/greenhouse/repo/` | `apps/ml-worker/` | ml-code | Running source for 5/6 ML systemd timers | ✅ yes | active-legacy | archive (after full migration) | all ML jobs break if deleted prematurely | n/a yet | `gh-predict-all` smoke with `PREDICT_LIMIT=1` from monorepo | critical | 18 GB repo; local caches `parquet_cache/` + `models_v4/` are derivatives |
| `apps/ml-worker/` | same | ml-code | Monorepo ML copy — partial migration; `refresh_registry` is only active job | ⚠️ partial | partial | replace (become SoT) | requires storage wiring + shell script fixes | storage wiring prerequisite | `PREDICT_LIMIT=1` from monorepo; storage backend smoke | critical | `.bak_phase2b/2c` = correct migrated versions, not yet applied |
| `apps/ml-worker/storage/` | same | ml-storage | Storage abstraction factory — complete, **not wired** | ❌ no | partial | keep (wire to callers) | blocks client-local ML | critical prerequisite | `STORAGE_BACKEND=supabase` predict smoke; then `STORAGE_BACKEND=local` | high | `backend.py` + `local_backend.py` + `s3_backend.py` + `supabase_backend.py` |
| `apps/ml-worker/jobs/run_predict_all.sh` | same | ml-scripts | systemd `ExecStart` — redirects to `/opt/greenhouse/repo` | ⚠️ broken | active-legacy | replace (fix in place) | shell path redirect must be removed | none yet | predict runs from monorepo `WorkingDirectory` | high | `cd /opt/greenhouse/repo` must become `cd $GH_REPO_DIR` |
| `apps/ml-worker/jobs/run_train_missing.sh` | same | ml-scripts | systemd `ExecStart` — redirects to `/opt/greenhouse/repo` | ⚠️ broken | active-legacy | replace (fix in place) | shell path redirect must be removed | none yet | train-missing runs from monorepo | high | Same issue as run_predict_all.sh |
| `apps/ml-worker/jobs/parquet_export/scripts/run_daily_parquet_batches.sh` | same | ml-scripts | systemd `ExecStart` — `PROJECT_DIR` hardcoded to legacy path | ⚠️ broken | active-legacy | replace (fix in place) | parquet export broken after ML migration | none yet | parquet export runs from monorepo path | high | `PROJECT_DIR="/opt/greenhouse/repo/..."` must use `GH_REPO_DIR` |
| **Supabase: `t_core_analytics__series_{gran}_{entity}`** (×16) | `client-runtime/sql/init/02_schema_7b1.sql` | analytics-sql | Pre-aggregated analytics series tables; read by `/analytics/series` | ✅ Supabase | active-canonical (cloud) · stub (CR) | keep cloud; stubs in CR ✅ | none | empty stubs → 200 empty; ETL needed to populate | verify `/analytics/series` → 200 empty in CR | low | All 16 granularity×entity combos. Wave 7B.1 complete. |
| **Supabase: `core_analytics__series_*_lc`** (×16 views) | `client-runtime/sql/init/02_schema_7b1.sql` | analytics-sql | Thin lowercase-normalising views; `/analytics/series` query path | ✅ Supabase | active-canonical (cloud) · stub (CR) | keep cloud; views in CR ✅ | none | views compile → endpoints 200 | `/analytics/series?granularity=day&entity_type=famiglia` → 200 | low | Wave 7B.1 complete |
| **Supabase: `t_core_analytics__breakdown_*`** (×12+) | `client-runtime/sql/init/` Wave 7B.2 | analytics-sql | Breakdown tables by granularity+entity; `/analytics/series-breakdown` | ✅ Supabase | active-canonical (cloud) · partial (CR) | keep cloud; port to CR | none | `/analytics/series-breakdown` → 500 if missing | breakdown endpoint → 200 empty | medium | Status after 7B.2A-J not fully verified |
| **Supabase: analytics RPCs** (`core_analytics__range_totals_v2`, `entity_hierarchy_tree_v1`, `stock_and_reorder_v1`, `future_window_stats_v2`, `search_catalog_rich`, `catalog_children`, `list_catalog`) | `client-runtime/sql/init/` Wave 7B.2 | analytics-sql | 7 plpgsql functions; Tier 3+4 endpoints | ✅ Supabase | active-canonical (cloud) · partial (CR) | keep cloud; port to CR | none | `/analytics/entity-summary` + others → 500 if missing | each RPC endpoint → 200 empty | medium | `pg_trgm` extension needed for catalog search |
| **Supabase: `t_core_analytics__seasonality_month`** + view | `client-runtime/sql/init/02_schema_7b1.sql` | analytics-sql | Seasonality data; `/analytics/seasonality` | ✅ Supabase | active-canonical (cloud) · stub (CR) ✅ | keep cloud; stub in CR ✅ | none | `/analytics/seasonality` → 200 empty ✅ | `/analytics/seasonality` → 200 | low | Wave 7B.1 complete |
| **Supabase: `t_dashboard_sales_{daily,weekly,monthly,yearly}`** (×4) | `client-runtime/sql/init/02_schema_7b1.sql` | dashboard-sql | Dashboard aggregation tables; `/dashboard/sales-*` | ✅ Supabase | active-canonical (cloud) · stub (CR) ✅ | keep cloud; stubs in CR ✅ | none | `/dashboard/sales-*` → 200 empty ✅ | `/dashboard/sales-weekly` → 200 | low | Wave 7B.1 complete |
| **Supabase: `dashboard__sales_*` views** (×3) | `client-runtime/sql/init/02_schema_7b1.sql` | dashboard-sql | Thin views for dashboard endpoints | ✅ Supabase | active-canonical (cloud) · stub (CR) ✅ | keep cloud; views in CR ✅ | none | views compile ✅ | endpoint → 200 | low | Wave 7B.1 complete |
| **Supabase: `dashboard__kpis_v2()`** | `client-runtime/sql/init/` Wave 7B.2 | dashboard-sql | Multi-table KPI aggregation function; `/dashboard/kpis` | ✅ Supabase | active-canonical (cloud) · partial (CR) | keep cloud; port to CR | none | `/dashboard/kpis` → 500 if missing | endpoint → 200 empty | medium | High complexity; needs all analytics tables populated to be useful |
| **Supabase: `dashboard__reorder_suggestions_top`** view | `client-runtime/sql/init/` Wave 7B.2 | dashboard-sql | Join view; `/dashboard/reorder-suggestions` | ✅ Supabase | active-canonical (cloud) · partial (CR) | keep cloud; port to CR | none | endpoint → 500 if missing | endpoint → 200 empty | medium | Joins `greenhouse_products_normalized` + `greenhouse_stock_raw_upload` |
| **Supabase: `t_core_planner__*`** (×9 tables) | `client-runtime/sql/init/` Wave 7B.2 | planner-sql | Planner state tables; 8+ planner endpoints | ✅ Supabase | active-canonical (cloud) · partial (CR) | keep cloud; port to CR | none | planner endpoints → 500 if missing | planner stubs → 200 empty | medium | Populated by `nightly_roll4_tick()` from forecast data |
| **Supabase: planner RPCs** (8 functions: `core_planner__get_*`, `rpc_heatmap_week_pivot`) | `client-runtime/sql/init/` Wave 7B.3+ | planner-sql | Planner computation; heatmap, space-budget, assortment-calendar | ✅ Supabase | active-canonical (cloud) · blocked (CR) | keep cloud; port to CR later | none | all planner RPC endpoints → 500 | planner RPCs → 200 empty | high | Blocked until ML forecast pipeline portable; complex plpgsql |
| **Supabase: `ml_ops.pipeline_run_log_v1`**, **`ml_ops.family_run_log_v1`** | `client-runtime/sql/init/` Wave 7B.3 (planned) | ops-sql | ML ops log tables; `/ops/pipeline-status`, `/ops/family-runs` | ✅ Supabase | active-canonical (cloud) · not-started (CR) | keep cloud; port to CR | none | `/ops/pipeline-status` + `/ops/family-runs` → 500 | → 200 empty after Wave 7B.3 | medium | Simple DDL — 2 tables. High unlock value. |
| **Supabase: `ml_ops.v_pipeline_runs_recent_v1`**, **`v_daily_pipeline_summary_v1`** | `client-runtime/sql/init/` Wave 7B.3 (planned) | ops-sql | ML ops views; `/ops/pipeline-status`, `/ops/health` | ✅ Supabase | active-canonical (cloud) · not-started (CR) | keep cloud; port to CR | none | ops endpoints degraded/500 | → 200 after Wave 7B.3 | medium | Wraps `pipeline_run_log_v1`; low complexity |
| **Supabase: `t_ops_pipeline_monitor`** + **`v_ops_pipeline_status`** | `client-runtime/sql/init/` Wave 7B.3 (planned) | ops-sql | Ops monitoring table + view; `/ops/health` probe | ✅ Supabase | active-canonical (cloud) · not-started (CR) | keep cloud; port to CR | none | `/ops/health` probe 1 fails | → `ok` after Wave 7B.3 | medium | Small; belongs with ml_ops Wave 7B.3 |
| **Supabase: ETL functions** (`run_greenhouse_daily_pipeline_full`, `refresh_dense_range_from_fact`, `refresh_forecast_features_dense_range`, `refresh_core_analytics_range`, `refresh_dashboard_sales_range`, `etl` schema) | `client-runtime/sql/init/` Wave 7B.4+ | etl-sql | Full ETL pipeline; populates all analytics/forecast tables | ✅ Supabase | active-canonical (cloud) · not-started (CR) | keep cloud; port to CR | none (ETL runs via pg_cron) | without ETL, DB never populated from raw data | ETL runs locally; `etl.t_etl_runs` shows SUCCESS | critical | Most complex porting task; requires local scheduler equivalent |
| **Supabase: `greenhouse_forecast_results_v2`** | `client-runtime/sql/init/02_schema_7b1.sql` | forecast-sql | ML prediction output; `/forecast/*`, planner | ✅ Supabase | active-canonical (cloud) · stub (CR) ✅ | keep cloud; stub in CR ✅ | none | `/forecast/summary` → 200 empty ✅ | `/forecast/summary` → 200 | low | Stub present since Wave 7B.1 |
| **Supabase: `ml_forecast.family_model_registry_v2`** | `client-runtime/sql/init/` Wave 7B.4+ (deferred) | ml-forecast-sql | Model routing registry; used by `refresh_registry.py` | ✅ Supabase | active-canonical (cloud) · deferred (CR) | keep cloud; port to CR with ML pipeline | none (not in API query path) | ML routing absent on client | ML routing smoke test | medium | Not a backend API dependency; used by ML worker only |
| `/etc/systemd/system/gh-*.service|timer` (12 units) | `infra/systemd/` (via `install.sh`) | systemd | Live systemd units for all ML timers | ✅ yes | active-canonical | keep (manage via monorepo copy) | `daemon-reload` needed after any edit | NOT portable as-is | unit files deploy cleanly; timers fire | low | 9 `.bak*` files present — delete |
| `infra/systemd/current/` | `infra/systemd/` | systemd | Versioned mirror of live units — in sync | ⚠️ mirror | copied-idle | replace (flatten `current/`) | none | n/a | compare diff to `/etc/systemd/system/` | low | Flatten `current/` subdir; write `install.sh` |
| `infra/scripts/bin/` (21 scripts) | same | cli-scripts | Active CLI scripts for 4 systemd services + manual use | ✅ yes (4 services) | active-canonical | keep | PATH must be sole entry | not portable (paths hardcoded) | run each script; verify env loads correctly | medium | `gh-audit` broken (references missing `ml_monitor_db.py`) |
| `/opt/greenhouse/bin/` (19 scripts) | archive | cli-scripts | Legacy CLI scripts — still in PATH alongside monorepo | ❌ no (but in PATH) | active-legacy | archive (remove from PATH first) | ambiguous PATH resolution | n/a | manual test after PATH removal | critical | Same script names, different behavior — remove from PATH ASAP |
| `infra/env/base.env` + `infra/env/dev.env` (via `load_env.sh`) | same | env-config | Env system for 4 systemd services | ✅ yes (4 services) | active-canonical | keep | missing `SUPABASE_DB_*` aliases | `client.env` template exists | ML jobs work after adding `SUPABASE_DB_*` aliases | high | `SUPABASE_DB_*` missing → `export_features_dense.py` crashes |
| `/opt/greenhouse/.env` | archive | env-config | Legacy env for 2 systemd services (`EnvironmentFile=`) | ✅ yes (2 services) | active-legacy | archive (after migrating biweekly/quarterly) | biweekly/quarterly fail if removed prematurely | n/a | biweekly/quarterly run with `load_env.sh` | high | Migrate `gh-train-biweekly-all` + `gh-train-quarterly` to `load_env.sh` first |
| `/opt/greenbrain-v2/deploy/` (`docker-compose.*.yml` + `.env`) | `infra/docker/` | docker-deploy | Cloud Docker compose — all 6 `gb_v2_*` containers | ✅ yes | active-canonical | copy → `infra/docker/`; archive after volumes updated | all containers restart during transition | n/a | full stack smoke after compose update | medium | Volume mounts reference non-monorepo paths |
| `client-runtime/docker/docker-compose.yml` | same | docker-deploy | Client Docker stack — postgres + backend only | ✅ yes (for CR) | partial | keep + extend (add frontend after auth migrated) | n/a | backend + DB working; frontend + ML absent | backend `GET /health` → 200; DB connects | medium | No production Dockerfiles exist yet |
| `client-runtime/sql/init/01_bootstrap.sql` | same | client-runtime | Wave 7A — creates `_runtime_bootstrap` table | ✅ yes | complete | keep | n/a | Tier 0 (4 endpoints) ✅ | `SELECT * FROM _runtime_bootstrap` returns row | low | Complete |
| `client-runtime/sql/init/02_schema_7b1.sql` | same | client-runtime | Wave 7B.1 — 23 tables + 20 views → 27 endpoints at 200 | ✅ yes | complete | keep | n/a | 27 Tier-2 endpoints → 200 empty ✅ | run endpoint smoke suite | low | Complete |
| `client-runtime/sql/init/03–12_schema_7b2a-j.sql` (10 files) | same | client-runtime | Waves 7B.2A-J — Tier 3/4/5 partial coverage | ✅ yes | partial | keep + extend | n/a | ~11 more endpoints → 200; ~20 still 500 | verify exact endpoint coverage per wave | medium | Exact coverage not fully verified without reading each file |
| `client-runtime/sql/schema/endpoint-matrix.md` | same | cr-docs | Maps every endpoint → DB tier → wave | ✅ yes | complete | keep | n/a | planning reference | cross-check after each new wave | low | Key planning artefact |
| `client-runtime/sql/schema/object-inventory.md` | same | cr-docs | Maps every DB object needed per endpoint | ✅ yes | complete | keep | n/a | planning reference | cross-check after each new wave | low | Key planning artefact |
| `docs/migration/source-of-truth.md` | same | docs | Canonical SoT per domain (just created 2026-04-01) | ✅ yes | complete | keep + update on major changes | n/a | n/a | — | low | Created this session |
| `docs/analysis-stato-sistema-2026-04.md` | same | docs | Full system analysis + gap analysis + roadmap | ✅ yes | complete | keep + update on major changes | n/a | n/a | — | low | Created this session |
| `docs/operations/00-full-system-inventory-0{1,2,3}.md` | same | docs | Detailed system inventory (filesystem, processes, schema) | ✅ yes | complete | keep | n/a | n/a | — | low | Primary evidence base |
| `docs/migration/wave-7b2b-runbook.md` | same | docs | Runbook for Wave 7B.2B execution | ✅ yes | complete | keep | n/a | reference | — | low | |
| `greenbrain-v2/docs/` (12 files) | `docs/archive/greenbrain-v2/` | docs | Pre-migration architecture docs (stale) | ❌ no | active-legacy | archive | none | n/a | — | low | Superseded by `docs/` in monorepo |
| `apps/ml-worker/ISTRUZIONI*/lovabel .env corretto.json` | DELETE | security | **Live credentials in source tree** (Supabase JWT + DO Spaces secret) | — | active-legacy | **delete immediately** | rotate keys after delete | — | keys rotated; no jobs fail | **critical** | Also at `/opt/greenhouse/repo/ISTRUZIONI*/` and `docs/operations/env-live.txt` |
| `sql/` (directory) | `sql/schema/` + `sql/migrations/` + `sql/cron/` + `sql/seed/` | sql | Currently **empty** — intended schema home | ❌ no | not-started | create structure + populate | none (additive) | migration runner needed | `psql -f sql/migrations/001_*.sql` applies cleanly | medium | Must be populated before client-runtime can self-install |
| `/opt/greenbrain-v2/database/current-schema.sql` | `sql/schema/local-snapshot.sql` | sql | Schema snapshot from **local Docker DB** (not Supabase) | ⚠️ partial | active-legacy | copy → `sql/schema/`; re-export from Supabase | none | drift between Supabase and local DB is unknown | diff against Supabase pg_dump | high | May be stale; Supabase pg_dump needed for true snapshot |
| `jobs/migrations/blocco_*.sql` (8 files, both repos) | `sql/migrations/001-008_*.sql` | sql | Applied migration SQL — no runner, wrong directory | ⚠️ misplaced | active-legacy | copy to `sql/migrations/`; add runner; archive originals | none (already applied) | migration runner needed for future changes | `psql -f` each file in order; confirm idempotent | medium | Move only — files are historical (already applied to Supabase) |
| **Supabase `cron.job` table** (13 rows, 3 with `* * * * *`) | `sql/cron/pg_cron_canonical.sql` | sql | pg_cron job definitions — unversioned; 3 duplicate every-minute jobs | ✅ yes (runtime) | active-legacy | version in file; disable jobs #30/38/39 now | jobs #30/38/39 cause excessive ETL load | not portable (Supabase-only) | ETL runs correctly with only jobs #11/29/37 | **critical** | `SELECT cron.unschedule(30/38/39)` is safe and reversible |
| `apps/ml-worker/.bak_phase2b/2c` files (17 files) | DELETE after apply | ml-migration | In-progress migration artifacts — contain correct migrated versions | ⚠️ needed | partial | apply → then delete | none until applied | storage abstraction blocked | `PREDICT_LIMIT=1` smoke with `STORAGE_BACKEND=supabase` | high | Must apply `.bak_phase2b_fix` → `data_access_v1.py` first |
| `/opt/greenhouse/repo/parquet_cache/` (18520 files) | `/opt/greenhouse/cache/parquet/` (outside repo) | ml-cache | Local parquet cache — derivative of Supabase Storage | ❌ no (cache) | active-legacy | relocate (update `PARQUET_CACHE_DIR`); gitignore | none (hot cache) | `LOCAL_STORAGE_ROOT` replaces this on client | ML jobs still populate cache | low | 18 GB inflates repo size; safe to relocate |
| `/opt/greenhouse/repo/models_v4/` (1886 .pkl files) | outside repo tree | ml-cache | Local model bundle cache — derivative of DO Spaces | ❌ no (cache) | active-legacy | gitignore; relocate | none (warm cache) | `LOCAL_STORAGE_ROOT` used on client | model bundles still loaded from DO Spaces | low | Gitignore; add to `.gitignore` |

---

## Migration Blockers

These items **block other work** and cannot be bypassed without resolving the root cause.

| # | Blocker | Blocks | Resolution |
|---|---------|--------|------------|
| B1 | **Storage abstraction not wired** (4 ML files still call Supabase SDK directly) | ML monorepo unification; client-local ML; any non-Supabase deployment | Apply `.bak_phase2b_fix` → `data_access_v1.py`; apply remaining `.bak` to 3 files; smoke with `STORAGE_BACKEND=supabase` |
| B2 | **Frontend auth uses Supabase JS** (`integrations/supabase/client.ts`) | client-local login; production Dockerfile for frontend | Design + implement FastAPI JWT (`POST /auth/login`, `GET /auth/me`); replace `useGardenCenterSettings` hook |
| B3 | **ETL SQL functions not in client-runtime** (`run_greenhouse_daily_pipeline_full` + 5 sub-functions + `etl` schema) | DB ever being populated on client; planner; analytics being useful | Extract ETL functions from Supabase; port to `client-runtime/sql/init/` as Wave 7B.4 |
| B4 | **ML shell scripts redirect to legacy repo** (`cd /opt/greenhouse/repo` in ExecStart scripts) | ML monorepo becoming SoT; storage abstraction having any effect on running jobs | Replace `cd /opt/greenhouse/repo` with `cd $GH_REPO_DIR`; update `GH_REPO_DIR` in `dev.env` |
| B5 | **`SUPABASE_DB_*` naming gap in `dev.env`** | `export_features_dense.py` crashes when run from monorepo env | Add 5 `SUPABASE_DB_*=${PG_*}` aliases to `infra/env/dev.env` |
| B6 | **pg_cron jobs #30/38/39 — every-minute duplicates** | ETL stability; Supabase DB load | `SELECT cron.unschedule(30); cron.unschedule(38); cron.unschedule(39);` |
| B7 | **Credentials in source tree** (`lovabel .env corretto.json`, `env-live.txt`) | Security; must be rotated before any public repo exposure | Delete files; rotate Supabase JWT + DO Spaces secret |
| B8 | **No production Dockerfiles** for backend or frontend | client-local Docker deploy; cloud production build | Write `apps/backend/Dockerfile` and `apps/frontend/Dockerfile` (build + nginx) |
| B9 | **Planner RPCs depend on ML forecast output** which requires full ML pipeline on client | client-local planner functionality | Cannot unblock until B1 + B3 + ML pipeline portable |
| B10 | **`sql/` directory empty** — no migration runner, no versioned schema | Reproducible client install; schema change management | Export Supabase schema; move migration files; write `sql/migrate.sh` |

---

## Safe Moves That Can Be Done Now

No deployment restart, no production impact, no dependencies.

| # | Action | Files | Effort | Notes |
|---|--------|-------|--------|-------|
| S1 | **Disable pg_cron #30/38/39** | Supabase `cron.job` | 5 min | `SELECT cron.unschedule(30/38/39)` — reversible |
| S2 | **Delete credential files** + rotate keys | `lovabel .env corretto.json` (×2) + `env-live.txt` | 30 min | Rotate Supabase JWT + DO Spaces secret afterwards |
| S3 | **Add `SUPABASE_DB_*` aliases to `dev.env`** | `infra/env/dev.env` | 10 min | Additive only; unblocks B5 |
| S4 | **Delete 9 `.bak*` files from `/etc/systemd/system/`** | `/etc/systemd/system/*.bak*` | 5 min | Not loaded by systemd; pure clutter |
| S5 | **Apply ml_ops schema as Wave 7B.3** | `client-runtime/sql/init/13_schema_7b3.sql` (create) | 30 min | 2 tables + 3 views + 1 public view → unblocks `/ops/pipeline-status` + `/ops/family-runs` → 200 |
| S6 | **Delete `.bak` files from `apps/backend/`** | `app/core/config.py.bak`, `app/api/v1/ops.py.bak` | 5 min | Not imported anywhere |
| S7 | **Move 8 migration SQL files to `sql/migrations/`** | `jobs/migrations/blocco_*.sql` → `sql/migrations/001-008_*.sql` | 20 min | Historical files already applied — move is a rename |
| S8 | **Flatten `infra/systemd/current/` → `infra/systemd/`** + write `install.sh` | `infra/systemd/` | 20 min | No systemd reload needed; purely structural |
| S9 | **Gitignore `parquet_cache/`, `models_v4/`, `priors_cache/`, `__pycache__/`, `.bak*`** | `.gitignore` in both repos | 15 min | No runtime impact |
| S10 | **Apply `.bak_phase2b_fix` to `data_access_v1.py` in monorepo** | `apps/ml-worker/data_access_v1.py` | 20 min | Start of storage wiring; test with `STORAGE_BACKEND=supabase` + `PREDICT_LIMIT=1` — no behavior change expected |
| S11 | **Write `sql/cron/pg_cron_canonical.sql`** with 10 correct jobs | `sql/cron/` | 30 min | Documentation only; no DB change |
| S12 | **Copy `greenbrain-v2/docs/` → `docs/archive/greenbrain-v2/`** | 12 doc files | 5 min | Additive; stale docs safely archived |

---

## Moves That Must Wait

| # | Move | Waiting for | Dependency chain |
|---|------|-------------|-----------------|
| W1 | Update docker-compose frontend volume → `apps/frontend/` | B2 (auth replacement) + `.env` copied to `apps/frontend/` + production build works | B2 → frontend Dockerfile → compose update |
| W2 | Update docker-compose backend volume → `apps/backend/` | `apps/backend/Dockerfile` written + uvicorn starts cleanly | B8 → compose update |
| W3 | Remove `cd /opt/greenhouse/repo` from ML shell scripts | S3 (SUPABASE_DB_* aliases) + storage abstraction wired (B1) + `.bak` files applied | S3 → B1 → B4 |
| W4 | Migrate `gh-train-biweekly/quarterly` to `load_env.sh` | B5 resolved (all vars in `dev.env`); smoke test first | S3 → W4 |
| W5 | Archive `/opt/greenhouse/.env` | W4 complete — both services confirmed on `load_env.sh` | W4 → archive |
| W6 | Remove `/opt/greenhouse/bin/` from `$PATH` | `infra/scripts/bin/` confirmed as sole PATH entry; all operators aware | W4 → W6 |
| W7 | Archive `/opt/greenhouse/repo/` | All 6 systemd ML services confirmed running full daily cycle from monorepo | B1 + B4 + W3 + W4 + full daily smoke |
| W8 | Port ETL SQL functions to client-runtime (Wave 7B.4) | Supabase pg_dump schema extracted; ETL function SQL extracted + reviewed | B10 → W8 |
| W9 | Port planner RPCs to client-runtime (Wave 7B.5+) | ML forecast pipeline portable on client (so planner tables can be populated) | B1 + B3 + W8 → W9 |
| W10 | Write `client-runtime/packaging/install.sh` | B2 + B3 + B8 + production Dockerfiles exist + schema complete | All blockers → W10 |
| W11 | Replace `useGardenCenterSettings` Supabase call with FastAPI endpoint | FastAPI JWT auth implemented (B2) | B2 → W11 |
| W12 | `STORAGE_BACKEND=local` end-to-end test on clean machine | B1 fully applied to all 4 files + `LOCAL_STORAGE_ROOT` set + ML runs from monorepo | B1 + W3 → W12 |

---

*Cross-reference: `docs/migration/source-of-truth.md` · `docs/analysis-stato-sistema-2026-04.md`*
