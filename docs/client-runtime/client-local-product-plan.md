# Client-Local Product Plan — V1
> Execution plan to turn `client-runtime` into a real installable product
> for garden-center customers.
> Updated: 2026-04-02.
> Evidence: `docs/architecture/greenbrain-canonical-architecture.md` ·
> `docs/architecture/dev-cloud-vs-client-local.md` ·
> `docs/architecture/runtime-current-state.md` ·
> `docs/migration/source-of-truth.md`

---

## 1. Target Architecture (Customer Install)

A single-server Linux install. No Supabase account. No DigitalOcean. No internet
required at runtime.

```
Customer server (Linux, single-tenant)
│
├── Docker
│   ├── gb_v2_postgres  :5433   PostgreSQL 17 + pg_cron extension
│   ├── gb_v2_backend   :8002   FastAPI (same image as dev-cloud)
│   └── gb_v2_frontend  :80     React app (production build, nginx)
│
├── Local filesystem
│   └── $LOCAL_STORAGE_ROOT/
│       ├── parquet/             ML feature parquet files (per family+year)
│       ├── priors/              Prior distribution files
│       └── models/              Trained model bundles (.pkl)
│
├── Scheduler
│   ├── pg_cron (in PostgreSQL)  ETL functions + planner refresh nightly
│   └── cron / systemd           ML training + prediction timers
│
└── infra/env/client.env         All configuration; no Supabase vars
```

The customer interacts only with the frontend at `http://<server>/`.
All data — sales, forecasts, analytics, planner — lives in the local PostgreSQL
instance. All ML artifacts live on the local filesystem.

---

## 2. Minimum Sellable/Installable Runtime (V1)

**V1 is the minimum state where a real customer can install and use the product.**

A customer install is V1-complete when:
1. `./install.sh` runs on a clean Ubuntu 22.04 server without manual intervention
2. The customer can log in with username + password (no Supabase account)
3. Sales analytics are visible and non-empty (ETL has run at least once)
4. Dashboard sales views are non-empty
5. Reorder suggestions are populated (requires ETL + basic forecast data)
6. Data refreshes automatically overnight (ETL scheduler running)
7. ML predictions run on a schedule (basic forecast, reorder inputs)
8. `./update.sh` applies new schema waves and model bundles cleanly

### Must-have for V1

| Area | Requirement |
|------|------------|
| Auth | FastAPI JWT login; no Supabase dependency |
| Schema | All 13 current waves applied; ETL functions as Wave 7B.4 |
| ETL | Runs locally via pg_cron; populates analytics + dashboard tables |
| Analytics | Returns non-empty data after ETL run; series, breakdown, reorder |
| Dashboard | Sales views non-empty; reorder-suggestions populated |
| ML | Predict cycle runs locally with `STORAGE_BACKEND=local` |
| Storage | `LocalStorageBackend` wired; `$LOCAL_STORAGE_ROOT` on disk |
| Scheduler | pg_cron in local PostgreSQL for ETL; cron/systemd for ML |
| Frontend | Production build (nginx); no Vite dev server |
| Install | `install.sh` works cold; `update.sh` handles waves + models |

### Accepted stubs in V1

These are explicitly not required for a working V1. The product remains usable
without them. Each is documented to the customer as "coming soon" or "not available."

| Area | Stub behavior | Rationale |
|------|--------------|-----------|
| `dashboard/kpis` | 200 empty `{}` | Complex aggregation semantics deferred |
| `planner/*` (except calendar-events, current-week) | 200 empty `[]` | Requires ML forecast pipeline confirmed stable |
| `ops/pipeline-status` | 200 empty `[]` | ML ops logging requires ML pipeline first |
| `ops/family-runs` | 200 empty `[]` | Same |
| `catalog/children`, `catalog/list`, `catalog/search` | 200 empty `[]` | Enrichment deferred |
| `analytics/entity-summary` quantitative totals | Tree-only response | Accepted per `runtime-current-state.md` |

### Deferred post-V1

| Feature | Deferred until |
|---------|---------------|
| Full planner (8 RPCs + heatmap) | ML pipeline confirmed stable on client; nightly_roll4_tick verified |
| `dashboard/kpis` real implementation | KPI business semantics defined |
| Catalog enrichment (families, attributes) | Business decision on data source |
| Backup automation (`pg_dump` cron) | V1.1 — manual backup procedure documented for now |
| Multi-tenant support | Not in scope |
| Remote monitoring / telemetry | Not in scope |
| CI/CD for customer updates | Not in scope for V1 |

---

## 3. Area-by-Area Status

---

### 3.1 DB / Schema / Init Waves

**Current status:**
13 init files applied, confirmed working:
```
01_bootstrap.sql           Wave 7A   — system tables, _runtime_bootstrap marker
02_schema_7b1.sql          Wave 7B.1 — 23 tables + 20 views, 27 endpoints → 200
03–12_schema_7b2{a-j}.sql  Wave 7B.2 — Tier 3/4 analytics, RPCs, catalog
13_schema_7b3_ml_ops.sql   Wave 7B.3 — ml_ops schema (pipeline_run_log, family_run_log)
```
`_runtime_bootstrap` marker table records each applied wave. Init sequence is
idempotent and restartable.

**Missing:**
- Wave 7B.4: ETL plpgsql functions (`run_greenhouse_daily_pipeline_full` + 5 sub-functions)
- Wave 7B.5 (future): 8 planner RPCs (deferred to post-V1)
- `CREATE EXTENSION pg_cron` not yet in bootstrap — required for ETL scheduling
- `CREATE EXTENSION pg_trgm` presence in client PostgreSQL unconfirmed

**Blocker level:** Medium — Wave 7B.4 is the next concrete deliverable.

**Recommended next task:**
```
1. pg_dump --schema-only $SUPABASE_URL -n public > /tmp/supabase_public.sql
2. grep -A 200 "run_greenhouse_daily_pipeline_full" /tmp/supabase_public.sql
3. Audit extracted functions for Supabase-specific calls (auth.*, gen_random_uuid, vault.*)
4. Neutralize dependencies; write client-runtime/sql/init/14_schema_7b4_etl.sql
```

---

### 3.2 ETL

**Current status:**
ETL runs on Supabase cloud via 6 pg_cron jobs. It executes plpgsql functions that
read from `t_etl_input_*` tables, aggregate, and populate all analytics and dashboard
tables. Without ETL, every analytics and dashboard endpoint returns an empty response
in client-runtime — schema is present but data never flows.

**Missing:**
- ETL plpgsql functions not extracted or ported
- Local pg_cron schedule not defined
- `t_etl_runs` and ETL gate logic not in init files
- `infra/env/client.env` ETL vars not verified (no Supabase connection vars needed, but
  `ETL_BATCH_SIZE`, `ETL_LOOKBACK_DAYS` equivalents must be confirmed)

**Blocker level:** **High** — this is the single gate for analytics data on client.

**Recommended next task:**
Extract ETL functions from Supabase snapshot (`sql/schema/supabase-snapshot.sql`
if created, or direct pg_dump), audit each for cloud-specific SQL, neutralize, write
as Wave 7B.4. Then enable pg_cron in client Docker compose and load the ETL schedule.

**Known risk:** ETL functions may reference Supabase-specific behaviour:
- `gen_random_uuid()` → replace with `uuid_generate_v4()` or `uuid_in(md5(...)::cstring::uuid)`
- Any `auth.*` schema reference → eliminate (client has no auth schema)
- `realtime.*` → eliminate
- `NOTIFY` / `pg_notify` calls → evaluate and drop if used for Supabase webhooks

---

### 3.3 Analytics

> Analytics is a first-class, core component of the product. It is not optional.
> The frontend is built around analytics views. The planner depends on analytics
> forecasts. ETL exists to feed analytics tables.

**Current status:**
All analytics schema objects are present in client-runtime init files:
- 16 series tables + 16 `*_lc` views (Wave 7B.1)
- 12 breakdown tables + views (Wave 7B.2)
- `t_core_analytics__seasonality_month` + view (Wave 7B.1)
- 7 analytics RPCs (Wave 7B.2: range_totals, stock_and_reorder, future_window_stats,
  compare_series, entity_hierarchy_tree, etc.)

All analytics API endpoints return HTTP 200 with empty arrays. The contract is correct.
Data is absent because ETL has never run.

**Validated in dev-cloud (REAL / BUSINESS-VALIDATED or equivalent):**
- `/api/v1/analytics/series-breakdown` — REAL / BUSINESS-VALIDATED
- `/api/v1/analytics/future-windows-stats` — REAL / BUSINESS-VALIDATED
- `/api/v1/analytics/compare-series` — REAL / SEMANTICALLY-ACCEPTED
- `/api/v1/analytics/entity-summary` — REAL / STRUCTURE-VALIDATED (tree-only)

**Missing for V1:**
- ETL running locally (see §3.2)
- After ETL: verify series, breakdown, reorder endpoints return non-empty data

**Blocker level:** Tied to ETL (§3.2). Once ETL runs, analytics data will flow
through existing schema objects with no additional code changes.

**Recommended next task:** ETL porting (Wave 7B.4) — same as §3.2. Analytics has
no independent blockers beyond the ETL dependency.

---

### 3.4 Dashboard

**Current status:**
Schema in place via Wave 7B.1 + 7B.2C:
- `t_dashboard_sales_{daily,weekly,monthly,yearly}` (4 tables)
- Corresponding views
- `dashboard__reorder_suggestions_top` join view (Wave 7B.2C)
- `dashboard__kpis_v2()` function exists in init but returns stub

Endpoints:
- `/dashboard/sales-weekly`, `sales-monthly`, `sales-yearly` → 200 empty ✅
- `/dashboard/reorder-suggestions` → 200 empty (schema present; data needs ETL + ML)
- `/dashboard/kpis` → 200 empty (accepted stub for V1)

`dashboard/reorder-suggestions` is REAL / BUSINESS-VALIDATED in dev-cloud. It
requires both ETL-populated sales data AND ML forecast data for non-trivial output.

**Missing for V1:**
- ETL to populate `t_dashboard_sales_*` tables
- ML predict to populate `greenhouse_forecast_results_v2`
- Only after both: reorder-suggestions returns real data

**Blocker level:** High — tied to ETL + ML portability.
**Recommended next task:** Same as ETL (§3.2) and ML (§3.8).

---

### 3.5 Planner

**Current status:**
- `/planner/calendar-events` → 200 empty (tolerant, ProgrammingError caught) ✅
- `/planner/current-week` → safe date-math stub ✅
- All other planner endpoints → 500 (8 RPCs not in init files)

The planner depends on ML forecast data (`greenhouse_forecast_results_v2` populated)
and `nightly_roll4_tick()` scheduler. Both require a working ML pipeline first.

**V1 decision:** Planner is **accepted partial stub** for V1.
`calendar-events` and `current-week` work. All other planner endpoints will return
200 empty or a graceful stub. Full planner is post-V1.

**Missing for V1:** Nothing — accepted stub behavior is sufficient.
**Missing for post-V1:**
- 8 planner RPCs as Wave 7B.5
- `nightly_roll4_tick()` in pg_cron local schedule
- ML forecast data flowing locally

**Blocker level:** Low for V1 — stub is acceptable.

---

### 3.6 Ops

**Current status (Wave 7B.3 applied and working):**
- `/api/v1/ops/health` → `ok` ✅
- `/api/v1/ops/pipeline-status` → 200 empty ✅ (schema present; ML not writing locally yet)
- `/api/v1/ops/family-runs` → 200 empty ✅ (same reason)

`ml_ops.pipeline_run_log_v1` and `ml_ops.family_run_log_v1` tables exist in client
PostgreSQL. They will receive rows once ML jobs run with local storage.

**V1 decision:** Ops health check (`ok`) is required for V1. Pipeline monitoring
will populate automatically once ML pipeline is complete. No additional ops work
required for V1 beyond what Wave 7B.3 provides.

**Missing for V1:** Nothing blocking — current state is acceptable.
**Post-V1:** Alerting; log rotation policy; `t_ops_pipeline_monitor` automation.

**Blocker level:** None for V1.

---

### 3.7 Frontend

**Current status:**
- All data hooks use `apiClient.ts` → FastAPI — no Supabase data dependency
- Auth: `src/integrations/supabase/client.ts` + `useAuth.tsx` — Supabase JS, cloud-only
- Running as Vite dev server (not production build)
- Lock file conflict: both `package-lock.json` and `bun.lock` present
- `.env` with `VITE_SUPABASE_*` vars required at build time (cloud-only vars)

**Missing for V1:**
- `apps/frontend/Dockerfile` (Vite build + nginx) — does not exist
- FastAPI JWT auth hooks (see §3.9)
- `.env` without Supabase vars: only `VITE_API_BASE_URL=http://localhost:8002` needed
- Lock file conflict resolved

**Blocker level:** **Critical** — client-local install cannot start without a
production frontend image.

**Recommended next task:**
1. Implement FastAPI JWT auth (§3.9 first — frontend auth depends on backend)
2. Replace `useAuth.tsx` and `useGardenCenterSettings.ts`
3. Remove `@supabase/supabase-js`
4. Write `apps/frontend/Dockerfile`

---

### 3.8 Auth

**Current status:**
Supabase JS auth only. `integrations/supabase/client.ts` provides the auth client.
`useAuth.tsx` hooks into Supabase session. `Login.tsx` posts to Supabase.
No FastAPI auth endpoint exists. Client-local login is impossible in the current state.

**Missing for V1 (all required):**
- `apps/backend/app/api/v1/auth.py`:
  - `POST /api/v1/auth/login` — returns JWT
  - `GET /api/v1/auth/me` — returns user from JWT
- `GET /api/v1/settings/garden-center` — replaces `useGardenCenterSettings` direct query
- `src/hooks/useAuth.tsx` replaced with FastAPI JWT implementation
- `src/hooks/useGardenCenterSettings.ts` replaced with `apiClient.ts` call
- `src/pages/Login.tsx` updated
- `@supabase/supabase-js` removed from `package.json`
- `src/integrations/supabase/client.ts` deleted

**Blocker level:** **Critical** — this blocks the entire client-local product.

**Recommended next task:**
Write `apps/backend/app/api/v1/auth.py` first. Backend auth is independent of
frontend changes and can be deployed and tested immediately. Frontend replacement
follows after backend endpoint is live.

**Implementation guidance:**
- Use `python-jose` (JWT) + `passlib[bcrypt]` (password hashing)
- User table: confirm whether `public.users` or a dedicated `auth_users` table is
  appropriate for client-local (no Supabase `auth.*` schema)
- JWT secret: stored in `infra/env/client.env` as `JWT_SECRET`
- Token expiry: configurable via `JWT_EXPIRE_MINUTES`

---

### 3.9 ML Pipeline

**Current status:**
- Storage abstraction module complete: `LocalStorageBackend`, `S3StorageBackend`,
  `SupabaseStorageBackend`, `backend.py` factory
- 4 calling files still use direct SDK: `data_access_v1.py`, `export_features_dense.py`,
  `upload_priors_to_supabase.py`, `download_priors_from_supabase.py`
- `.bak_phase2b_fix` and `.bak_phase2c` migration files exist and are ready to apply
- 5 of 6 systemd ML jobs run from `/opt/greenhouse/repo/` (legacy)
- `STORAGE_BACKEND=local` has zero production effect until all 4 files are wired

**Missing for V1:**
1. Storage abstraction wired in all 4 ML files (`.bak_phase2b/2c` applied)
2. ML shell scripts fixed: `cd $GH_REPO_DIR` not `cd /opt/greenhouse/repo`
3. `STORAGE_BACKEND=local` predict cycle validated end-to-end
4. Client-local ML scheduler (see §3.11)
5. Initial model bundle delivery mechanism (how does the customer get the first
   trained models — bundled with install, or pulled from remote on first run?)

**Blocker level:** **Critical** — ML forecast data is required for reorder-suggestions.
Without ML, `dashboard/reorder-suggestions` returns empty forever.

**Recommended next task:**
Apply `.bak_phase2b_fix` to `data_access_v1.py`; smoke with `PREDICT_LIMIT=1
STORAGE_BACKEND=supabase` (no behavior change expected). Then apply remaining 3
files. Then fix shell scripts. Then test `STORAGE_BACKEND=local PREDICT_LIMIT=1`.

**V1 scope for ML:**
- ML predict cycle runs locally from `apps/ml-worker/` with `STORAGE_BACKEND=local`
- `greenhouse_forecast_results_v2` is populated in local PostgreSQL after each run
- Training cycle (biweekly/quarterly) is out of scope for V1 initial install
  (customer ships with pre-trained models; retraining added in V1.1)

---

### 3.10 Storage

**Current status:**
`apps/ml-worker/storage/` factory is complete and correct:
```
backend.py              # get_storage_backend() factory — reads STORAGE_BACKEND env var
local_backend.py        # LocalStorageBackend — reads/writes $LOCAL_STORAGE_ROOT
s3_backend.py           # S3StorageBackend
supabase_backend.py     # SupabaseStorageBackend
```

`STORAGE_BACKEND=local` → `LocalStorageBackend` → `$LOCAL_STORAGE_ROOT/`.
4 ML files still bypass the factory entirely (direct SDK calls).

**Missing for V1:**
- Wire all 4 files (`.bak_phase2b/2c`)
- `LOCAL_STORAGE_ROOT` set in `infra/env/client.env` (currently present as template)
- Directory structure under `LOCAL_STORAGE_ROOT` created at install time:
  `$LOCAL_STORAGE_ROOT/parquet/`, `$LOCAL_STORAGE_ROOT/priors/`, `$LOCAL_STORAGE_ROOT/models/`
- Initial model bundles present in `$LOCAL_STORAGE_ROOT/models/` before first predict run

**Blocker level:** **Critical** — everything else depends on this being wired.

**Recommended next task:** Apply `.bak_phase2b_fix` to `data_access_v1.py` as
documented in `docs/migration/dev-cloud-execution-plan.md` §4.1.

---

### 3.11 Scheduler

**Current status:**
- Supabase pg_cron: 10 correct ETL + planner jobs running in cloud
- systemd timers: 6 ML jobs on cloud host
- Client-local: **no scheduler of any kind**

**Missing for V1:**
1. `CREATE EXTENSION IF NOT EXISTS pg_cron;` in client PostgreSQL Docker
   (add to `client-runtime/docker/docker-compose.yml` or `01_bootstrap.sql`)
2. ETL pg_cron schedule for client: `sql/cron/client-variant.sql` — defines the 6
   ETL jobs pointing to local DB (no Supabase connection string)
3. ML scheduler for client: lightweight `cron` entries or systemd units for
   `gh-predict-all` equivalent on the customer server
4. Schedule timing for client: ETL at 02:00 nightly; ML predict at 03:00 nightly
   (after ETL completes)

**Blocker level:** High — ETL and ML never run automatically without this.

**Recommended next task:**
Add pg_cron extension to `client-runtime/sql/init/01_bootstrap.sql`:
```sql
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```
Then write `client-runtime/sql/cron/client-etl-schedule.sql` with ETL jobs.

---

### 3.12 Install / Update / Backup / Restore

**Current status:**
- `client-runtime/docker/docker-compose.yml` — exists and correct
- `client-runtime/sql/init/` — 13 files, works correctly
- `install.sh` — **does not exist**
- `update.sh` — **does not exist**
- Backup strategy — **not designed**

**Missing for V1 (all required):**

**install.sh must:**
```
1. Check: Docker, Docker Compose, Python 3.11+, ports 80+8002+5433 free
2. docker-compose up -d postgres
3. Wait for postgres to be ready (pg_isready loop)
4. Apply sql/init/*.sql in numeric order via psql
5. docker-compose up -d backend frontend
6. Create initial admin user (POST /api/v1/auth/setup)
7. Create LOCAL_STORAGE_ROOT directories
8. Pull/unpack initial model bundles to LOCAL_STORAGE_ROOT/models/
9. docker-compose up -d (scheduler container or cron setup)
10. Print: URL, default credentials, health check command
```

**update.sh must:**
```
1. docker-compose pull (pull latest images)
2. Apply any new sql/init/*.sql files not yet in _runtime_bootstrap
3. Pull new model bundles if version file changed
4. docker-compose up -d (rolling restart)
5. Run smoke: curl /health && curl /api/v1/ops/health
```

**Backup (V1 — manual procedure, not automated):**
```bash
# Run by customer or via scheduled cron
pg_dump -h localhost -p 5433 -U $PG_USER $PG_DATABASE > backup_$(date +%Y%m%d).sql
tar czf models_backup_$(date +%Y%m%d).tar.gz $LOCAL_STORAGE_ROOT/models/
```
Automated backup cron is V1.1.

**Restore procedure:**
```bash
docker-compose stop backend frontend
psql -h localhost -p 5433 -U $PG_USER $PG_DATABASE < backup_YYYYMMDD.sql
tar xzf models_backup_YYYYMMDD.tar.gz -C $LOCAL_STORAGE_ROOT/
docker-compose start backend frontend
```

**Blocker level:** Medium — blocked by all upstream items (auth, ETL, ML, storage,
scheduler) being complete first. `install.sh` is the integration step.

---

## 4. V1 Dependency Chain

The correct sequencing for unblocking V1 in minimum time:

```
[1] Storage abstraction wired (.bak_phase2b/2c)
      ↓
[2] ML shell scripts fixed (cd $GH_REPO_DIR)
      ↓
[3] STORAGE_BACKEND=local predict cycle validated
      ↓
[4] pg_cron + pg_trgm extensions in client Docker
      ↓
[5] Wave 7B.4: ETL functions ported to client-runtime init
      ↓
[6] ETL schedule in client pg_cron → analytics data flows
      ↓
[7] FastAPI JWT auth endpoints (POST /auth/login, GET /auth/me)
      ↓
[8] Frontend: replace useAuth.tsx; remove Supabase JS
      ↓
[9] apps/frontend/Dockerfile (production nginx build)
      ↓
[10] install.sh + update.sh written and cold-tested
```

Steps [1]–[3] (storage + ML) and steps [4]–[6] (ETL + scheduler) can be worked
in parallel by two people. Steps [7]–[10] (auth + frontend + install) must be
sequential.

---

## 5. Client-Local V1 Definition of Done

### Auth
- [ ] `POST /api/v1/auth/login` returns a valid JWT
- [ ] `GET /api/v1/auth/me` returns user profile from JWT
- [ ] Login works in browser without any Supabase account
- [ ] Frontend has zero `@supabase/supabase-js` dependency

### Schema and ETL
- [ ] All 14 init waves apply cleanly on a fresh PostgreSQL 17 container
- [ ] `_runtime_bootstrap` records all 14 waves applied
- [ ] ETL functions run without error in local PostgreSQL (Wave 7B.4)
- [ ] pg_cron extension active; ETL jobs scheduled; at least one successful ETL run
- [ ] `t_core_analytics__series_*` tables are non-empty after ETL run
- [ ] `t_dashboard_sales_*` tables are non-empty after ETL run

### Analytics (must not be empty after ETL run)
- [ ] `/api/v1/analytics/series?granularity=day&entity_type=famiglia` → non-empty
- [ ] `/api/v1/analytics/series-breakdown` → non-empty
- [ ] `/api/v1/analytics/future-windows-stats` → non-empty
- [ ] `/api/v1/analytics/compare-series` → non-empty
- [ ] `/api/v1/dashboard/sales-weekly` → non-empty
- [ ] `/api/v1/dashboard/reorder-suggestions` → non-empty (requires ML forecast too)

### ML
- [ ] Predict cycle runs with `STORAGE_BACKEND=local`; no error
- [ ] `greenhouse_forecast_results_v2` is non-empty after predict run
- [ ] ML predict runs on schedule (cron/systemd) — at least one scheduled run completed
- [ ] Pre-trained model bundles present in `LOCAL_STORAGE_ROOT/models/` after install

### Frontend
- [ ] `apps/frontend/Dockerfile` builds; production nginx image serves the app
- [ ] Browser loads dashboard after login
- [ ] Analytics charts render with real data
- [ ] `VITE_API_BASE_URL` is the only required env var at build time

### Install
- [ ] `install.sh` completes on clean Ubuntu 22.04 without manual intervention
- [ ] System is usable within 1 hour of starting `install.sh` (after ETL first run)
- [ ] `update.sh` applies a new init wave file without data loss
- [ ] Manual backup procedure documented and tested: `pg_dump` + model bundle tar

### Ops / Health
- [ ] `GET /api/v1/ops/health` → `ok`
- [ ] `GET /health/db` → healthy
- [ ] `/api/v1/ops/pipeline-status` → 200 (may be empty if ML hasn't run yet)

---

## 6. Client-Local V1 Not-in-Scope

The following are explicitly out of scope for V1. They are not missing — they are
intentionally deferred.

| Item | Reason | Target |
|------|--------|--------|
| Planner RPCs (8 functions) | Requires ML forecast stable on client; complex RPCs | V1.1 |
| `nightly_roll4_tick()` planner scheduler | Depends on planner RPCs | V1.1 |
| `dashboard/kpis` real implementation | KPI business semantics undefined | V1.1 |
| ML retraining on client (biweekly/quarterly) | Customer ships with pre-trained models; retraining risky without monitoring | V1.1 |
| Automated backup cron | Manual procedure documented; automation after stability confirmed | V1.1 |
| Catalog enrichment | No customer request yet | V1.1 |
| Multi-tenant support | Single-tenant product; multi-tenant requires auth redesign | V2 |
| Remote management / telemetry | Privacy concern; not requested | V2 |
| CI/CD for customer update pipeline | Manual `update.sh` sufficient for V1 | V2 |
| Windows or macOS install | Linux only for V1 | V2 |
| HTTPS / TLS certificate management | Customer's responsibility for V1; can use Caddy/Nginx in V1.1 | V1.1 |
| Cloud backup to remote storage | Local backup only for V1 | V1.1 |
| `analytics/entity-summary` quantitative totals | Tree-only accepted; totals require schema redesign | V1.1+ |

---

*For the dev-cloud counterpart execution plan, see
`docs/migration/dev-cloud-execution-plan.md`.*
*For the full migration sequence across both modes, see
`docs/architecture/master-roadmap-to-product.md`.*
*For current endpoint validation state, see
`docs/architecture/runtime-current-state.md`.*


---

> **Note:** The brand/domain model is confirmed (`greenbrain.it`, `<slug>.greenbrain.it`).
> Customer remote access via subdomain is gated on this plan being complete.
> Platform completion — this document — comes first.
> See `docs/architecture/final-platform-priority-and-access-decision.md`.
