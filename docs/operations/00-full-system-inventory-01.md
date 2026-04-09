# Full System Inventory — Part 1 of 3
# Phases 1–3: Repository Map · Execution Entrypoints · Scheduling
> Generated: 2026-03-27. Evidence-based from filesystem scan, process list, systemd unit files,
> pg_cron query. No assumptions.

---

## 1. Repository Map

### Top-level directories under /opt

| Path | Size | Classification | Status |
|------|------|---------------|--------|
| `/opt/greenhouse` | 18 GB | **Active ML runtime (legacy)** | All systemd ML jobs ultimately run Python from here |
| `/opt/greenbrain-platform` | 12 GB | **New monorepo (partially active)** | Shell entry scripts migrated here; Python runs from greenhouse |
| `/opt/greenbrain-v2` | 82 MB | **Backend + SQL schema + Docker stack** | Running in Docker containers on ports 8002/8082/8083 |
| `/opt/greenbrain` | 369 MB | **Production frontend** | Running in Docker via gb_v2_frontend on port 8083 |
| `/opt/digitalocean` | 27 MB | **Infrastructure agent** | DigitalOcean droplet agent + DO agent |
| `/opt/containerd` | 4 KB | **System** | Permission denied — system containerd |

---

### /opt/greenhouse — Active ML Runtime

```
/opt/greenhouse/
├── .env                          ← LIVE production env (primary source for ML jobs)
├── .env.bak_20260304_005544      ← backup
├── bin/                          ← CLI scripts (legacy set, still active)
│   ├── gh-audit                  active
│   ├── gh-audit-ops              active
│   ├── gh-audit.bak_20260307_115013
│   ├── gh-monitor                active
│   ├── gh-predict-all            active (differs from monorepo version)
│   ├── gh-predict-all-now        active
│   ├── gh-predict-all-test       active
│   ├── gh-predict-family         active
│   ├── gh-refresh-ml-diag        active
│   ├── gh-refresh-registry       active (differs from monorepo version)
│   ├── gh-sync-local-artifacts   active
│   ├── gh-train-all              active
│   ├── gh-train-all-now          active
│   ├── gh-train-all-test         active
│   ├── gh-train-biweekly-all     active
│   ├── gh-train-family           active
│   ├── gh-train-missing          active (differs from monorepo version)
│   ├── gh-train-one              active
├── logs/                         ← runtime logs (predict_all_*, train_missing_*, parquet_export/*)
├── ml_monitor_archive/           ← CSV snapshots of ML registry
├── models_v4_backup/             ← models_v4_20260221_092011.tgz (backup archive)
├── repo/                         ← MAIN ML PYTHON CODEBASE (source of truth for running code)
│   ├── data_access_v1.py
│   ├── predict_v4_single_family_tweedie.py
│   ├── train_v4_single_family_tweedie.py
│   ├── jobs/                     ← orchestrator Python modules
│   │   ├── predict_all.py        ← called by run_predict_all.sh
│   │   ├── train_missing_batches.py ← called by run_train_missing.sh
│   │   ├── train_all_monitor.py  ← called by biweekly + quarterly services
│   │   ├── refresh_registry.py
│   │   ├── engines/              ← 8 model engines
│   │   ├── parquet_export/       ← export_features_dense.py + run_daily_parquet_batches.sh
│   │   └── ...
│   ├── scripts/spaces_io.py      ← DO Spaces boto3 wrappers (still imported by ensure_model_bundle)
│   ├── tools/build_seasonal_priors.py
│   ├── requirements.txt
│   ├── parquet_cache/            ← runtime: 18520 parquet files
│   ├── models_v4/                ← runtime: 1886 .pkl model bundles
│   └── priors_cache/             ← runtime: 847 items
├── tmp/                          ← lock files (predict_all.lock, train_missing.lock, etc.)
└── venv/                         ← Python virtual env (used by ALL systemd ML jobs)
```

---

### /opt/greenbrain-platform — New Monorepo (Partially Active)

```
/opt/greenbrain-platform/
├── apps/
│   ├── ml-worker/                ← COPY of ML codebase (diverged from /opt/greenhouse/repo)
│   │   ├── data_access_v1.py     DIVERGED: .bak_phase2b files present — migration in progress
│   │   ├── jobs/                 DIVERGED: 9 files differ from /opt/greenhouse/repo/jobs/
│   │   │   ├── run_predict_all.sh          ACTIVE (ExecStart for gh-predict-all.service)
│   │   │   ├── run_train_missing.sh        ACTIVE (ExecStart for gh-train-missing.service)
│   │   │   ├── parquet_export/             ACTIVE (ExecStart for gh-parquet-export.service)
│   │   │   └── ...
│   │   ├── storage/              NEW: StorageBackend abstraction (local/s3/supabase) — NOT yet wired
│   │   │   ├── backend.py
│   │   │   ├── local_backend.py
│   │   │   ├── s3_backend.py
│   │   │   └── supabase_backend.py
│   │   └── ...
│   ├── backend/                  ← FastAPI backend (identical to greenbrain-v2/backend minus .env.example)
│   └── frontend/                 ← React frontend (src/ identical to /opt/greenbrain/frontend/src/)
├── docs/                         ← architecture, discovery, migration, operations docs
├── infra/
│   ├── env/
│   │   ├── base.env              ← common config (STORAGE_BACKEND, GB_ROOT)
│   │   ├── dev.env               ← Supabase DB + supabase storage
│   │   └── client.env            ← local DB + local storage
│   ├── scripts/
│   │   ├── load_env.sh           ← env loader: merges base.env + $APP_ENV.env
│   │   ├── bin/                  ← UPDATED CLI scripts (newer than /opt/greenhouse/bin/)
│   │   └── runtime/              ← additional runtime scripts
│   └── systemd/current/          ← versioned copy of systemd unit files (12 units)
└── sql/                          ← (empty — migrations not yet moved here)
```

---

### /opt/greenbrain-v2 — Backend + SQL Schema + Docker Stack

```
/opt/greenbrain-v2/
├── backend/                      ← FastAPI backend (RUNNING in Docker)
│   ├── app/main.py               ← mounts 9 routers
│   ├── app/api/v1/               ← analytics, catalog, dashboard, forecast, ops, planner, sales, system
│   ├── app/core/config.py        ← reads POSTGRES_* env vars
│   └── requirements.txt
├── database/
│   ├── current-schema.sql        ← full Supabase schema export (~170 tables/views/functions)
│   ├── backups/                  ← 3 SQL backup files (pre-pg17, pg17-clean, local)
│   ├── famiglie_catalog_static_data.sql ← static family catalog data
│   └── forecast-results-data.sql ← forecast results data
├── deploy/
│   ├── .env                      ← live Docker env (POSTGRES_*)
│   ├── .env.client               ← client-local Docker env
│   ├── docker-compose.base.yml   ← service definitions (backend, frontend, ml, nginx, pgadmin, postgres)
│   ├── docker-compose.client.yml ← client override (adds postgres:17 + pgadmin)
│   ├── docker-compose.dev.yml    ← dev override
│   └── scripts/                  ← up/down/status scripts
├── docs/                         ← 12 architecture/migration docs
├── frontend/                     ← MINIMAL frontend (4 files) — NOT the production frontend
└── sandbox/
    ├── postgres17/               ← PostgreSQL 17 data directory (permission denied from host)
    └── postgres/                 ← (permission denied)
```

---

### /opt/greenbrain — Production Frontend (Docker)

```
/opt/greenbrain/
└── frontend/                     ← React + Vite + TailwindCSS + shadcn/ui
    ├── .env                      VITE_SUPABASE_URL + VITE_API_BASE_URL=http://127.0.0.1:8002
    ├── src/                      ← IDENTICAL to /opt/greenbrain-platform/apps/frontend/src/
    │   ├── integrations/supabase/ ← supabase client (auth + settings)
    │   ├── hooks/                 ← 20+ data hooks using apiClient.ts → FastAPI
    │   ├── features/planner/     ← assortment planner components
    │   ├── pages/                ← Dashboard, Analytics, AssortmentPlanner, Login, etc.
    │   └── lib/apiClient.ts      ← all data calls via VITE_API_BASE_URL
    ├── package.json
    └── bun.lock / bun.lockb / package-lock.json  ← 3 lock files: npm + bun (conflict)
```

---

### Running Docker Containers (live at scan time)

| Container | Image | Status | Ports |
|-----------|-------|--------|-------|
| `gb_v2_frontend` | node:20-alpine | Up 7 days | 0.0.0.0:**8083**→8080 |
| `gb_v2_backend` | python:3.11-slim | Up 5 days | 0.0.0.0:**8002**→8000 |
| `gb_v2_nginx` | nginx:alpine | Up 7 days | 0.0.0.0:**8082**→80 |
| `gb_v2_ml` | python:3.11-slim | Up 7 days | *(none — sleep infinity placeholder)* |
| `gb_v2_pgadmin` | dpage/pgadmin4:8 | Up 7 days | 0.0.0.0:**5050**→80 |
| `gb_v2_postgres` | postgres:17 | Up 7 days (healthy) | 0.0.0.0:**5433**→5432 |

> **Note:** `gb_v2_ml` container runs `sleep infinity` — it is a placeholder, not a working ML worker.
> All actual ML jobs run via systemd on the host, using `/opt/greenhouse/venv`.

---

### /opt/digitalocean — DigitalOcean System Agents

```
/opt/digitalocean/
├── bin/do-agent              ← DigitalOcean monitoring agent
├── bin/droplet-agent         ← DigitalOcean droplet agent
├── do-agent/scripts/update.sh
└── droplet-agent/scripts/update.sh
```

---

## 2. Execution Entrypoints

### 2.1 Systemd-Triggered Flows

Each systemd service chain is documented below. Working directory and env loading differ per service.

---

#### Flow A: `gh-predict-all.service`
```
/etc/systemd/system/gh-predict-all.service
  WorkingDirectory: /opt/greenbrain-platform/apps/ml-worker
  ExecStart: bash jobs/run_predict_all.sh
    ↓
  /opt/greenbrain-platform/apps/ml-worker/jobs/run_predict_all.sh
    cd /opt/greenhouse/repo            ← SWITCHES TO LEGACY REPO
    source /opt/greenhouse/venv/bin/activate
    source /opt/greenbrain-platform/infra/scripts/load_env.sh
    ↓
    1) psql → /tmp/slugs_all.txt (family slugs from famiglie_catalog_static)
    2) python -m tools.build_seasonal_priors --slugs-file /tmp/slugs_all.txt
         → /opt/greenhouse/repo/tools/build_seasonal_priors.py
    3) python -m jobs.upload_priors_to_supabase
         → /opt/greenhouse/repo/jobs/upload_priors_to_supabase.py
    4) python -m jobs.download_priors_from_supabase
         → /opt/greenhouse/repo/jobs/download_priors_from_supabase.py
    5) python -m jobs.predict_all
         → /opt/greenhouse/repo/jobs/predict_all.py
              → subprocess: python predict_v4_single_family_tweedie.py <family>
```

---

#### Flow B: `gh-train-missing.service`
```
/etc/systemd/system/gh-train-missing.service
  WorkingDirectory: /opt/greenbrain-platform/apps/ml-worker
  ExecStart: bash jobs/run_train_missing.sh
  ExecStartPost: /opt/greenbrain-platform/infra/scripts/bin/gh-sync-local-artifacts
    ↓
  /opt/greenbrain-platform/apps/ml-worker/jobs/run_train_missing.sh
    cd /opt/greenhouse/repo            ← SWITCHES TO LEGACY REPO
    source /opt/greenhouse/venv/bin/activate
    source /opt/greenbrain-platform/infra/scripts/load_env.sh
    ↓
    python -m jobs.train_missing_batches
         → /opt/greenhouse/repo/jobs/train_missing_batches.py
              → subprocess: python train_v4_single_family_tweedie.py <family>
    ↓
  ExecStartPost → python -m jobs.sync_local_artifacts
         → /opt/greenhouse/repo/jobs/sync_local_artifacts.py
```

---

#### Flow C: `gh-train-biweekly-all.service`
```
/etc/systemd/system/gh-train-biweekly-all.service
  WorkingDirectory: /opt/greenhouse/repo          ← RUNS DIRECTLY FROM LEGACY REPO
  EnvironmentFile: /opt/greenhouse/.env
  ExecStart: python3 -u jobs/train_all_monitor.py (RUN_TRIGGER_SOURCE=systemd_timer)
  ExecStartPost: /opt/greenhouse/bin/gh-sync-local-artifacts  ← legacy bin!
    ↓
  /opt/greenhouse/repo/jobs/train_all_monitor.py
       → subprocess: python train_v4_single_family_tweedie.py <family>
```

---

#### Flow D: `gh-train-quarterly.service`
```
/etc/systemd/system/gh-train-quarterly.service
  WorkingDirectory: /opt/greenhouse/repo          ← RUNS DIRECTLY FROM LEGACY REPO
  EnvironmentFile: /opt/greenhouse/.env
  ExecStart: python3 -u /opt/greenhouse/repo/jobs/train_all_monitor.py (absolute path)
             (also captures GIT_SHA via git rev-parse)
  ExecStartPost: /opt/greenhouse/bin/gh-sync-local-artifacts  ← legacy bin!
```

---

#### Flow E: `gh-parquet-export.service`
```
/etc/systemd/system/gh-parquet-export.service
  WorkingDirectory: /opt/greenbrain-platform/apps/ml-worker
  ExecStartPre: bash jobs/parquet_export/check_etl_ready.sh
    ↓
    check_etl_ready.sh:
      source /opt/greenbrain-platform/infra/scripts/load_env.sh
      psql: checks etl.t_etl_runs for success + raw_max match → exits 0 (READY) or 1
  ExecStart: bash jobs/parquet_export/scripts/run_daily_parquet_batches.sh
    ↓
    run_daily_parquet_batches.sh:
      PROJECT_DIR="/opt/greenhouse/repo/jobs/parquet_export"  ← SWITCHES TO LEGACY REPO
      cd "$PROJECT_DIR"
      for offset in 0 50 100 ... 800:
        python -u export_features_dense.py   ← /opt/greenhouse/repo/jobs/parquet_export/export_features_dense.py
```

---

#### Flow F: `gh-refresh-registry.service`
```
/etc/systemd/system/gh-refresh-registry.service
  WorkingDirectory: /opt/greenbrain-platform/apps/ml-worker
  ExecStartPre: source load_env.sh && /opt/greenbrain-platform/infra/scripts/bin/gh-refresh-ml-diag
    ↓ gh-refresh-ml-diag: REFRESH 9 ml_diag materialized views via psql
  ExecStart: /opt/greenbrain-platform/infra/scripts/bin/gh-refresh-registry
    ↓ gh-refresh-registry (monorepo version):
      cd /opt/greenbrain-platform/apps/ml-worker
      python3 -u -m jobs.refresh_registry    ← runs from MONOREPO (not legacy!)
```

> **Note:** `gh-refresh-registry` is the ONLY service that actually runs Python from the monorepo.
> All other services that run Python either switch to `/opt/greenhouse/repo` or use `EnvironmentFile`
> pointing to `/opt/greenhouse/.env`.

---

### 2.2 Manual CLI Scripts

Both `/opt/greenhouse/bin/` and `/opt/greenbrain-platform/infra/scripts/bin/` exist and are in PATH.
The versions **differ** (see Phase 7). Key invocation differences:

| Script | greenhouse/bin version | monorepo version |
|--------|----------------------|-----------------|
| `gh-refresh-registry` | `source /opt/greenhouse/.env; python3 -u jobs/refresh_registry.py` | `source load_env.sh; python3 -u -m jobs.refresh_registry` |
| `gh-train-missing` | `source /opt/greenhouse/.env; python3 -u jobs/train_missing_batches.py` | `source load_env.sh; python3 -u -m jobs.train_missing_batches` |
| `gh-predict-all` | `source /opt/greenhouse/.env; python3 -u jobs/predict_all.py` | `source load_env.sh; python3 -u -m jobs.predict_all` |

Full list of CLI scripts (both sets contain same names):

| Script | Purpose |
|--------|---------|
| `gh-audit` | Full health check: timers, processes, DB connectivity, log sizes |
| `gh-audit-ops` | Lighter ops check: recent runs, failures |
| `gh-monitor` | Live process monitor (ps-based) |
| `gh-predict-all` | Manually trigger predict_all |
| `gh-predict-all-now` | Force predict_all immediately (no lock check) |
| `gh-predict-all-test` | Test predict with PREDICT_LIMIT=1 |
| `gh-predict-family` | Predict single family |
| `gh-refresh-ml-diag` | REFRESH 9 ml_diag materialized views |
| `gh-refresh-registry` | Run refresh_registry.py |
| `gh-sync-local-artifacts` | Run sync_local_artifacts.py |
| `gh-train-all` | Manually trigger train_all_monitor |
| `gh-train-all-now` | Force train all |
| `gh-train-all-test` | Test train with TRAIN_LIMIT=1 |
| `gh-train-biweekly-all` | Manual trigger for biweekly train |
| `gh-train-family` | Train single family |
| `gh-train-missing` | Run train_missing_batches |
| `gh-train-one` | Single-family train via model_control.py |

---

### 2.3 Python Module Invocations (complete list)

All Python modules invoked by the above scripts, with their resolved paths:

| Module invocation | Resolved path (active runtime) |
|------------------|-------------------------------|
| `python -m jobs.predict_all` | `/opt/greenhouse/repo/jobs/predict_all.py` |
| `python -m jobs.train_missing_batches` | `/opt/greenhouse/repo/jobs/train_missing_batches.py` |
| `python3 -u jobs/train_all_monitor.py` | `/opt/greenhouse/repo/jobs/train_all_monitor.py` |
| `python -m tools.build_seasonal_priors` | `/opt/greenhouse/repo/tools/build_seasonal_priors.py` |
| `python -m jobs.upload_priors_to_supabase` | `/opt/greenhouse/repo/jobs/upload_priors_to_supabase.py` |
| `python -m jobs.download_priors_from_supabase` | `/opt/greenhouse/repo/jobs/download_priors_from_supabase.py` |
| `python -u export_features_dense.py` | `/opt/greenhouse/repo/jobs/parquet_export/export_features_dense.py` |
| `python3 -u -m jobs.refresh_registry` | `/opt/greenbrain-platform/apps/ml-worker/jobs/refresh_registry.py` ← ONLY one from monorepo |
| `python -m jobs.sync_local_artifacts` | `/opt/greenhouse/repo/jobs/sync_local_artifacts.py` |

---

### 2.4 Docker-Container Entrypoints

| Container | Command | Source volume |
|-----------|---------|---------------|
| `gb_v2_backend` | `uvicorn app.main:app --host 0.0.0.0 --port 8000` | `/opt/greenbrain-v2/backend:/app` |
| `gb_v2_frontend` | `npm install && npm run dev -- --host 0.0.0.0 --port 8080` | `/opt/greenbrain/frontend:/app` |
| `gb_v2_nginx` | nginx | `/opt/greenbrain-v2/deploy/nginx.conf` (implicit) |
| `gb_v2_ml` | `sleep infinity` | `/opt/greenbrain-v2/ml:/app` ← placeholder, does nothing |
| `gb_v2_pgadmin` | gunicorn run_pgadmin:app | internal |
| `gb_v2_postgres` | postgres:17 | `/opt/greenbrain-v2/sandbox/postgres17` |

> **Note:** Frontend uses `npm run dev` — **Vite development server**, not a production build.

---

## 3. Scheduling Layer

### 3.1 Systemd Timers (6 active, all enabled in timers.target.wants)

| Timer | Schedule | Service | What runs |
|-------|----------|---------|-----------|
| `gh-refresh-registry.timer` | **00:45** daily | gh-refresh-registry.service | gh-refresh-ml-diag → jobs/refresh_registry.py |
| `gh-train-missing.timer` | **01:10** daily | gh-train-missing.service | run_train_missing.sh → jobs.train_missing_batches |
| `gh-predict-all.timer` | **01:30** daily | gh-predict-all.service | run_predict_all.sh → build_priors → predict_all |
| `gh-train-biweekly-all.timer` | **Sun 1st+15th 02:00** | gh-train-biweekly-all.service | jobs/train_all_monitor.py (biweekly) |
| `gh-train-quarterly.timer` | **Jan/Apr/Jul/Oct 1st 02:30** | gh-train-quarterly.service | /opt/greenhouse/repo/jobs/train_all_monitor.py |
| `gh-parquet-export.timer` | **21:35** daily | gh-parquet-export.service | check_etl_ready → run_daily_parquet_batches.sh |

All timers have `Persistent=true` (catch up missed runs) and `RandomizedDelaySec` (120–900s jitter).

---

### 3.2 Daily Execution Timeline

```
21:35  gh-parquet-export   → export features_dense to Supabase Storage (parquet)
                              requires ETL to have succeeded today (check_etl_ready.sh)
                              runs 17 batches of 50 families each (~850 total)

00:45  gh-refresh-registry → REFRESH 9 ml_diag MVs → refresh family registry
                              updates ml_forecast.family_model_registry_v1/v2

01:10  gh-train-missing    → train families with missing model bundles
                              → ExecStartPost: sync local artifacts

01:30  gh-predict-all      → build seasonal priors → upload/download priors
                              → predict all families → write greenhouse_forecast_results_v2

~weekly (Sun 1st+15th, 02:00)
       gh-train-biweekly-all → force-retrain ALL families

~quarterly (1st of Jan/Apr/Jul/Oct, 02:30)
       gh-train-quarterly   → force-retrain ALL families (full refresh)
```

---

### 3.3 pg_cron Jobs (running on Supabase PostgreSQL)

All 13 jobs queried from `cron.job` table on 2026-03-27:

| jobid | schedule | command | status |
|-------|----------|---------|--------|
| 11 | `*/5 10-11 * * *` | `run_greenhouse_daily_pipeline_full(40,14,2)` | Active (window: 10:00–11:55) |
| 12 | `5 1 * * *` | `core_planner__nightly_roll4_reset()` | Active (01:05 daily) |
| 13 | `0 12 * * *` | `core_planner__nightly_roll4_tick(2)` | Active (noon daily) |
| 28 | `*/15 * * * *` | `ops_pipeline_monitor_snapshot()` | Active (every 15m) |
| 29 | `*/5 19-23 * * *` | `ops_maybe_run_daily_pipeline()` | Active (gated, evening) |
| **30** | **`* * * * *`** | **`run_greenhouse_daily_pipeline_full(40,14,2)`** | ⚠️ **CRITICAL: every 1 minute** |
| 31 | `*/10 19-23 * * *` | `ops_refresh_pipeline_monitor_snapshot()` | Active |
| 32 | `*/2 10-12 * * *` | `ops_refresh_pipeline_monitor_snapshot()` | Active |
| 34 | `*/30 0-9,13-23 * * *` | `ops_refresh_pipeline_monitor_snapshot()` | Active |
| 35 | `*/5 9-11 * * *` | `ops_refresh_pipeline_monitor_snapshot()` | Active |
| 37 | `*/5 9-11 * * *` | `ops_maybe_run_daily_pipeline()` | Active (gated) |
| **38** | **`* * * * *`** | **`ops_maybe_run_daily_pipeline()`** | ⚠️ **CRITICAL: every 1 minute** |
| **39** | **`* * * * *`** | **`run_greenhouse_daily_pipeline_full(40,14,2)`** | ⚠️ **CRITICAL: every 1 minute** |

**Critical pg_cron conflicts:**
- Jobs **30** and **39** both call `run_greenhouse_daily_pipeline_full(40,14,2)` every minute. During
  the 10:00–11:55 window, this overlaps with job **11** (also `run_greenhouse_daily_pipeline_full`).
  This means at peak hours the full ETL pipeline may be invoked **3+ times simultaneously per minute**.
- Job **38** calls `ops_maybe_run_daily_pipeline()` every minute (gated but still excessive load).
- Jobs 30, 38, 39 are almost certainly duplicates from iterative setup. Only one of 30/39 should run
  the full pipeline (with guard), and job 38 overlaps with job 29 (same function).

---

### 3.4 Full ETL → ML Execution Chain

```
pg_cron (Supabase) ──────────────────────────────────────────────────────────────
  job 11/30/39: run_greenhouse_daily_pipeline_full(40, 14, 2)
    → calls: refresh_dense_range(start, end)
    → calls: refresh_forecast_features_dense_range(start, end)
    → calls: refresh_core_analytics_tables(...)
    → writes to: etl.t_etl_runs (status=success on completion)

  job 12: core_planner__nightly_roll4_reset()   → resets planner state
  job 13: core_planner__nightly_roll4_tick(2)   → advances planner

systemd (host) ───────────────────────────────────────────────────────────────────
  21:35 gh-parquet-export:
    check_etl_ready.sh → verifies etl.t_etl_runs has success for today
    run_daily_parquet_batches.sh → 17 batches
      → export_features_dense.py (batch_offset=0,50,...800)
        → reads: public.greenhouse_forecast_features_dense
        → writes: Supabase Storage ml-snapshots/features_dense/v1/year=Y/slug=S/part.parquet
        → writes: public.ops_parquet_export_runs + ops_parquet_export_state

  00:45 gh-refresh-registry:
    gh-refresh-ml-diag → REFRESH 9 ml_diag.mv_* (reads greenhouse_* tables)
    gh-refresh-registry → refresh_registry.py
      → reads: ml_forecast.v_family_execution_routing_v2
      → writes: ml_forecast.family_model_registry_v1/v2

  01:10 gh-train-missing:
    train_missing_batches.py
      → reads: ml_forecast.v_train_missing_candidates_v1
      → for each missing family:
          ensure_model_bundle.py → check DO Spaces → download if exists
          train_v4_single_family_tweedie.py
            → reads: parquet (Supabase Storage) or DB (fallback)
            → writes: DO Spaces models_v4/bundle_<slug>_v4.pkl
            → writes: ml_forecast.family_model_state_v1
            → writes: ml_ops.family_run_log_v1
            → writes: ml_forecast.model_artifact_registry_v1

  01:30 gh-predict-all:
    build_seasonal_priors.py → builds priors_cache/priors_v1.parquet
    upload_priors_to_supabase → uploads to Supabase Storage
    download_priors_from_supabase → downloads back (ensures consistency)
    predict_all.py
      → reads: public.famiglie_catalog_static (all families)
      → reads: ml_forecast.family_model_registry_v1/v2
      → for each family:
          ensure_model_bundle.py → downloads model from DO Spaces
          predict_v4_single_family_tweedie.py
            → reads: parquet (Supabase Storage) or DB (fallback)
            → reads: priors_cache/priors_v1.parquet
            → writes: public.greenhouse_forecast_results_v2
            → writes: public.t_forecast_fam_daily
            → writes: ml_ops.family_run_log_v1 + pipeline_run_log_v1
```
