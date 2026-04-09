# Repo Structure Proposal
> Evidence-based. All paths verified by directory scan of `/opt/greenbrain-platform`, `/opt/greenhouse/repo`, `/opt/greenbrain/frontend`, `/opt/greenbrain-v2`.

---

## 1. Proposed Directory Tree

```
greenbrain-platform/
│
├── apps/
│   ├── backend/                              # FastAPI — already present, clean
│   │   ├── app/
│   │   │   ├── api/
│   │   │   │   ├── health.py
│   │   │   │   └── v1/
│   │   │   │       ├── analytics.py
│   │   │   │       ├── catalog.py
│   │   │   │       ├── dashboard.py
│   │   │   │       ├── forecast.py
│   │   │   │       ├── ops.py
│   │   │   │       ├── planner.py
│   │   │   │       ├── sales.py
│   │   │   │       └── system.py
│   │   │   ├── core/
│   │   │   │   └── config.py
│   │   │   ├── db/
│   │   │   │   └── session.py
│   │   │   └── main.py
│   │   ├── requirements.txt
│   │   └── README.md
│   │
│   ├── frontend/                             # React + Vite + Tailwind
│   │   ├── src/
│   │   │   ├── components/
│   │   │   ├── features/
│   │   │   ├── hooks/
│   │   │   ├── integrations/
│   │   │   ├── lib/
│   │   │   ├── pages/
│   │   │   ├── App.tsx
│   │   │   ├── index.css
│   │   │   └── main.tsx
│   │   ├── public/
│   │   ├── supabase/
│   │   ├── index.html
│   │   ├── package.json
│   │   ├── vite.config.ts
│   │   ├── tailwind.config.ts
│   │   ├── tsconfig.json
│   │   ├── tsconfig.app.json
│   │   ├── tsconfig.node.json
│   │   ├── postcss.config.js
│   │   ├── eslint.config.js
│   │   ├── components.json
│   │   └── README.md
│   │
│   └── ml-worker/                            # Python ML pipeline
│       ├── data_access_v1.py                 # shared data loader (parquet-first)
│       ├── predict_v4_single_family_tweedie.py
│       ├── train_v4_single_family_tweedie.py
│       ├── requirements.txt                  # single canonical (see §4)
│       │
│       ├── jobs/                             # orchestration + engines
│       │   ├── engines/
│       │   │   ├── engine_croston.py
│       │   │   ├── engine_ets.py
│       │   │   ├── engine_naive_zero.py
│       │   │   ├── engine_sarima.py
│       │   │   ├── engine_seasonal_croston.py
│       │   │   ├── engine_tsb.py
│       │   │   ├── engine_validation.py
│       │   │   ├── fascia_allocator.py
│       │   │   ├── forecast_writer.py
│       │   │   └── __init__.py
│       │   ├── parquet_export/
│       │   │   ├── export_features_dense.py
│       │   │   ├── check_etl_ready.sh
│       │   │   ├── scripts/
│       │   │   │   └── run_daily_parquet_batches.sh
│       │   │   └── README.md
│       │   ├── benchmark_family.py
│       │   ├── diagnose_families.py
│       │   ├── download_priors_from_supabase.py
│       │   ├── dump_families.py
│       │   ├── ensure_model_bundle.py
│       │   ├── family_resolver.py
│       │   ├── ml_ops_bridge.py
│       │   ├── model_control.py
│       │   ├── predict_all.py
│       │   ├── predict_family_router.py
│       │   ├── refresh_registry.py
│       │   ├── seasonality_gate.py
│       │   ├── sync_local_artifacts.py
│       │   ├── train_all_monitor.py
│       │   ├── train_family_router.py
│       │   ├── train_missing_batches.py
│       │   ├── update_family_state.py
│       │   ├── upload_priors_to_supabase.py
│       │   ├── validate_engines.py
│       │   └── __init__.py
│       │
│       ├── scripts/                          # systemd entry-point shell scripts
│       │   ├── run_predict_all.sh            # ← moved from jobs/
│       │   ├── run_train_missing.sh          # ← moved from jobs/
│       │   └── train_one_safe.sh             # ← moved from jobs/
│       │
│       ├── tools/
│       │   ├── build_seasonal_priors.py
│       │   └── hurdle_report.py
│       │
│       ├── maintenance/                      # NEW group: manual one-off tools
│       │   ├── backfill_dense_weekly.py      # ← moved from ml-worker root
│       │   ├── backfill_fact_weekly.py       # ← moved from ml-worker root
│       │   ├── backfill_features_weekly.py   # ← moved from ml-worker root
│       │   ├── patch_holidays_features_weekly.py  # ← moved from ml-worker root
│       │   ├── refresh_weekday_strength.py   # ← moved from ml-worker root
│       │   └── sync_holidays.py              # ← moved from ml-worker root
│       │
│       ├── analysis/                         # NEW group: analysis / backtest tools
│       │   ├── backtest_v4_family_plus_fasce.py   # ← moved from ml-worker root
│       │   ├── backtest_v4_family_total.py        # ← moved from ml-worker root
│       │   └── evaluate_v4_forecast.py            # ← moved from ml-worker root
│       │
│       └── tests/
│           └── test_spaces.py                # ← moved from ml-worker root
│
├── sql/
│   ├── schema/
│   │   └── current-schema.sql                # ← move from greenbrain-v2/database/
│   ├── migrations/
│   │   ├── blocco_a_migration.sql            # ← move from apps/ml-worker/jobs/migrations/
│   │   ├── blocco_b_migration.sql
│   │   ├── blocco_c_migration.sql
│   │   ├── blocco_c1_migration.sql
│   │   ├── blocco_d_migration.sql
│   │   ├── blocco_d1_migration.sql
│   │   ├── blocco_f_migration.sql
│   │   └── blocco_g_migration.sql
│   ├── cron/
│   │   └── pg_cron_canonical.sql             # canonical deduplicated pg_cron setup
│   └── diagnostics/
│       └── (diagnostic query files)
│
├── infra/
│   ├── bin/                                  # ← flattened from infra/scripts/bin/
│   │   ├── gh-audit
│   │   ├── gh-audit-ops
│   │   ├── gh-monitor
│   │   ├── gh-predict-all
│   │   ├── gh-predict-all-now
│   │   ├── gh-predict-all-test
│   │   ├── gh-predict-family
│   │   ├── gh-refresh-ml-diag
│   │   ├── gh-refresh-registry
│   │   ├── gh-sync-local-artifacts
│   │   ├── gh-train-all
│   │   ├── gh-train-all-now
│   │   ├── gh-train-all-test
│   │   ├── gh-train-biweekly-all
│   │   ├── gh-train-family
│   │   ├── gh-train-missing
│   │   └── gh-train-one
│   ├── systemd/                              # ← copy from /etc/systemd/system/ (source of truth)
│   │   ├── gh-parquet-export.service
│   │   ├── gh-parquet-export.timer
│   │   ├── gh-predict-all.service
│   │   ├── gh-predict-all.timer
│   │   ├── gh-refresh-registry.service
│   │   ├── gh-refresh-registry.timer
│   │   ├── gh-train-biweekly-all.service
│   │   ├── gh-train-biweekly-all.timer
│   │   ├── gh-train-missing.service
│   │   ├── gh-train-missing.timer
│   │   ├── gh-train-quarterly.service
│   │   └── gh-train-quarterly.timer
│   ├── deploy/
│   │   └── (deploy scripts)
│   └── env/
│       └── .env.example                      # non-secret template only
│
├── client-runtime/
│   ├── base/
│   ├── packaging/
│   └── templates/
│
└── docs/
    ├── architecture/
    │   └── 01-target-architecture.md
    ├── discovery/
    │   ├── 01-architecture-map.md
    │   ├── 02-systemd-jobs.md
    │   └── 03-table-dependency-graph.md
    ├── operations/
    │   ├── 01-live-schedules.md
    │   ├── 02-job-catalog.md
    │   ├── env-live.txt
    │   ├── pg_cron_jobs.txt
    │   ├── services-live.txt
    │   └── timers-live.txt
    ├── migration/
    │   ├── 01-repo-consolidation-plan.md
    │   └── 02-repo-structure-proposal.md     ← this file
    └── client-runtime/

```

**Explicit omissions from source tree** (runtime data — must be `.gitignore`d):
```
apps/ml-worker/models_v4/           # 1886 binary .pkl files — DO Spaces is source of truth
apps/ml-worker/parquet_cache/       # 18520 parquet files — Supabase Storage is source of truth
apps/ml-worker/priors_cache/        # 847 files
apps/ml-worker/logs/
apps/ml-worker/diagnostics/family_diagnostics.csv
apps/ml-worker/backfill_features_progress.json
apps/ml-worker/patch_holidays_progress.json
apps/ml-worker/__pycache__/         # and all nested __pycache__ dirs
```

---

## 2. Files to Move

### 2a — SQL: migrations out of ml-worker

| Source (current) | Destination (proposed) |
|-----------------|----------------------|
| `apps/ml-worker/jobs/migrations/blocco_a_migration.sql` | `sql/migrations/blocco_a_migration.sql` |
| `apps/ml-worker/jobs/migrations/blocco_b_migration.sql` | `sql/migrations/blocco_b_migration.sql` |
| `apps/ml-worker/jobs/migrations/blocco_c_migration.sql` | `sql/migrations/blocco_c_migration.sql` |
| `apps/ml-worker/jobs/migrations/blocco_c1_migration.sql` | `sql/migrations/blocco_c1_migration.sql` |
| `apps/ml-worker/jobs/migrations/blocco_d_migration.sql` | `sql/migrations/blocco_d_migration.sql` |
| `apps/ml-worker/jobs/migrations/blocco_d1_migration.sql` | `sql/migrations/blocco_d1_migration.sql` |
| `apps/ml-worker/jobs/migrations/blocco_f_migration.sql` | `sql/migrations/blocco_f_migration.sql` |
| `apps/ml-worker/jobs/migrations/blocco_g_migration.sql` | `sql/migrations/blocco_g_migration.sql` |

### 2b — SQL: schema from greenbrain-v2

| Source (current) | Destination (proposed) |
|-----------------|----------------------|
| `/opt/greenbrain-v2/database/current-schema.sql` (26874 lines) | `sql/schema/current-schema.sql` |

### 2c — Shell entry scripts: out of jobs/ into scripts/

These are systemd `ExecStart` targets and should be separate from Python job modules:

| Source (current) | Destination (proposed) |
|-----------------|----------------------|
| `apps/ml-worker/jobs/run_predict_all.sh` | `apps/ml-worker/scripts/run_predict_all.sh` |
| `apps/ml-worker/jobs/run_train_missing.sh` | `apps/ml-worker/scripts/run_train_missing.sh` |
| `apps/ml-worker/jobs/train_one_safe.sh` | `apps/ml-worker/scripts/train_one_safe.sh` |

### 2d — Root-level Python: maintenance tools

These one-off scripts are currently at `apps/ml-worker/` root with no grouping:

| Source (current) | Destination (proposed) |
|-----------------|----------------------|
| `apps/ml-worker/backfill_dense_weekly.py` | `apps/ml-worker/maintenance/backfill_dense_weekly.py` |
| `apps/ml-worker/backfill_fact_weekly.py` | `apps/ml-worker/maintenance/backfill_fact_weekly.py` |
| `apps/ml-worker/backfill_features_weekly.py` | `apps/ml-worker/maintenance/backfill_features_weekly.py` |
| `apps/ml-worker/patch_holidays_features_weekly.py` | `apps/ml-worker/maintenance/patch_holidays_features_weekly.py` |
| `apps/ml-worker/refresh_weekday_strength.py` | `apps/ml-worker/maintenance/refresh_weekday_strength.py` |
| `apps/ml-worker/sync_holidays.py` | `apps/ml-worker/maintenance/sync_holidays.py` |

### 2e — Root-level Python: analysis tools

| Source (current) | Destination (proposed) |
|-----------------|----------------------|
| `apps/ml-worker/backtest_v4_family_plus_fasce.py` | `apps/ml-worker/analysis/backtest_v4_family_plus_fasce.py` |
| `apps/ml-worker/backtest_v4_family_total.py` | `apps/ml-worker/analysis/backtest_v4_family_total.py` |
| `apps/ml-worker/evaluate_v4_forecast.py` | `apps/ml-worker/analysis/evaluate_v4_forecast.py` |
| `apps/ml-worker/test_spaces.py` | `apps/ml-worker/tests/test_spaces.py` |

### 2f — Infra: flatten bin path

| Source (current) | Destination (proposed) | Reason |
|-----------------|----------------------|--------|
| `infra/scripts/bin/gh-*` (18 files) | `infra/bin/gh-*` | Remove extra `scripts/` nesting level; `bin/` is canonical |

### 2g — Infra: systemd units (currently not in monorepo)

These exist only at `/etc/systemd/system/`. They should be versioned in the monorepo:

| Source (current, production) | Destination (proposed) |
|------------------------------|----------------------|
| `/etc/systemd/system/gh-parquet-export.service` | `infra/systemd/gh-parquet-export.service` |
| `/etc/systemd/system/gh-parquet-export.timer` | `infra/systemd/gh-parquet-export.timer` |
| `/etc/systemd/system/gh-predict-all.service` | `infra/systemd/gh-predict-all.service` |
| `/etc/systemd/system/gh-predict-all.timer` | `infra/systemd/gh-predict-all.timer` |
| `/etc/systemd/system/gh-refresh-registry.service` | `infra/systemd/gh-refresh-registry.service` |
| `/etc/systemd/system/gh-refresh-registry.timer` | `infra/systemd/gh-refresh-registry.timer` |
| `/etc/systemd/system/gh-train-biweekly-all.service` | `infra/systemd/gh-train-biweekly-all.service` |
| `/etc/systemd/system/gh-train-biweekly-all.timer` | `infra/systemd/gh-train-biweekly-all.timer` |
| `/etc/systemd/system/gh-train-missing.service` | `infra/systemd/gh-train-missing.service` |
| `/etc/systemd/system/gh-train-missing.timer` | `infra/systemd/gh-train-missing.timer` |
| `/etc/systemd/system/gh-train-quarterly.service` | `infra/systemd/gh-train-quarterly.service` |
| `/etc/systemd/system/gh-train-quarterly.timer` | `infra/systemd/gh-train-quarterly.timer` |

---

## 3. Files to Mark Legacy

Files that exist in the monorepo but are superseded, one-time-use patches, or informal artifacts:

| File | Reason | Action |
|------|--------|--------|
| `apps/ml-worker/jobs/train_all_batches.py` | Superseded by `train_all_monitor.py` (parallel workers, mlops integration) | Mark `# LEGACY` header; remove from systemd |
| `apps/ml-worker/jobs/run_train_all_parallel.sh` | Superseded by `gh-train-biweekly-all` systemd service which uses `train_all_monitor.py` directly | Mark legacy |
| `apps/ml-worker/jobs/run_train_all_until_done.sh` | Loop-retry wrapper, superseded by systemd `Persistent=true` + retry logic in `train_missing_batches.py` | Mark legacy |
| `apps/ml-worker/jobs/run_train_missing_until_done.sh` | Same — superseded | Mark legacy |
| `apps/ml-worker/analysis/fetch_forecast_dataset.py` | Superseded by `fetch_forecast_dataset_v2.py` | Mark legacy |
| `apps/ml-worker/scripts/patch_get_engine_urlcreate.py` | One-time patch script — already applied | Mark legacy; move to `maintenance/_applied_patches/` |
| `apps/ml-worker/scripts/patch_predict_safe.py` | One-time patch script — already applied | Mark legacy; move to `maintenance/_applied_patches/` |
| `apps/ml-worker/tools/season_gate_helper_v1.txt` | Plain text scratch note, not code | Convert to `docs/` markdown or delete |
| `apps/ml-worker/"ISTRUZIONI & FUNZIONAMENTO"/` | Informal docs folder with spaces in name; contains two JSON "documentation" files (`Funzionamento tabella _DENSE.json`, `lovabel .env corretto.json`) | Extract content to `docs/` markdown, delete folder |

**Files to delete outright** (no content value):

| File | Reason |
|------|--------|
| `apps/ml-worker/tools/build_seasonal_priors.py.bak_20260304_110508` | Backup file — version control supersedes .bak files |
| `apps/backend/app/core/config.py.bak` | Backup file |
| `apps/backend/app/api/v1/ops.py.bak` | Backup file |
| `infra/scripts/bin/gh-audit.bak_20260307_115013` | Backup file |
| `apps/ml-worker/backfill_features_progress.json` | Runtime state file |
| `apps/ml-worker/patch_holidays_progress.json` | Runtime state file |

---

## 4. Conflicts and Duplicates

### CRITICAL — pg_cron: duplicate/conflicting jobs

From `docs/operations/pg_cron_jobs.txt`:

| jobid | Schedule | Command | Status |
|-------|----------|---------|--------|
| 11 | `*/5 10-11 * * *` | `run_greenhouse_daily_pipeline_full(40,14,2)` | **Redundant** — overlaps with jobid 29 window |
| 29 | `*/5 19-23 * * *` | `ops_maybe_run_daily_pipeline()` | **Intended** — evening ETL window |
| 30 | `* * * * *` | `run_greenhouse_daily_pipeline_full(40,14,2)` | **CONFLICT** — fires every minute, bypasses ops gate |
| 37 | `*/5 9-11 * * *` | `ops_maybe_run_daily_pipeline()` | **Redundant** — morning window duplicate of 11 |
| 38 | `* * * * *` | `ops_maybe_run_daily_pipeline()` | **CONFLICT** — fires every minute |
| 39 | `* * * * *` | `run_greenhouse_daily_pipeline_full(40,14,2)` | **CONFLICT** — fires every minute, bypasses gate |
| 12 | `5 1 * * *` | `core_planner__nightly_roll4_reset()` | OK |
| 13 | `0 12 * * *` | `core_planner__nightly_roll4_tick(2)` | OK |
| 28 | `*/15 * * * *` | `ops_pipeline_monitor_snapshot()` | OK |
| 31 | `*/10 19-23 * * *` | `ops_refresh_pipeline_monitor_snapshot()` | Redundant with 28 |
| 32 | `*/2 10-12 * * *` | `ops_refresh_pipeline_monitor_snapshot()` | Redundant with 28 |
| 34 | `*/30 0-9,13-23 * * *` | `ops_refresh_pipeline_monitor_snapshot()` | Redundant with 28 |
| 35 | `*/5 9-11 * * *` | `ops_refresh_pipeline_monitor_snapshot()` | Redundant with 28 |

**Summary:** Jobs 30, 38, 39 each fire **every minute** and call the full ETL pipeline. The advisory lock in `run_greenhouse_daily_pipeline_full` prevents concurrent execution, but the scheduling is clearly wrong. These should be disabled. The intended production schedule should be only `jobid 29` (`*/5 19-23`).

**Proposed canonical `sql/cron/pg_cron_canonical.sql`:**
```sql
-- KEEP
select cron.schedule('etl_daily_evening',   '*/5 19-23 * * *',   'select public.ops_maybe_run_daily_pipeline()');
select cron.schedule('planner_roll4_reset', '5 1 * * *',         'select public.core_planner__nightly_roll4_reset()');
select cron.schedule('planner_roll4_tick',  '0 12 * * *',        'select public.core_planner__nightly_roll4_tick(2)');
select cron.schedule('pipeline_monitor',    '*/15 * * * *',      'select public.ops_pipeline_monitor_snapshot()');

-- DELETE: jobids 11, 30, 31, 32, 34, 35, 37, 38, 39
```

---

### HIGH — Frontend: two sources of truth

`apps/frontend/` and `/opt/greenbrain/frontend/` appear to be byte-for-byte copies (same `README.md` 2102 bytes, same lockfile sizes). However they diverge in one place:

| Path | `supabase/` |
|------|-------------|
| `apps/frontend/supabase/` | 0 items |
| `/opt/greenbrain/frontend/supabase/` | 1 item |

**Conflict:** Production frontend is at `/opt/greenbrain/frontend/`. The monorepo copy may be stale on `supabase/`. One canonical source must be chosen and the other must be derived from it.

**Resolution required:** Confirm `apps/frontend/src/` is identical to `/opt/greenbrain/frontend/src/` before treating monorepo as source of truth.

---

### HIGH — ml-worker: runtime data committed to source tree

The monorepo currently contains live runtime data that belongs in object storage:

| Path | Item count | Should live at |
|------|-----------|----------------|
| `apps/ml-worker/models_v4/` | 1886 `.pkl` files | DO Spaces `models_v4/` |
| `apps/ml-worker/parquet_cache/` | 18520 parquet files | Supabase Storage `ml-snapshots/` |
| `apps/ml-worker/priors_cache/` | 847 files | Supabase Storage `ml-snapshots/priors/` |
| `apps/ml-worker/logs/` | 4 log files | Server filesystem only |
| `apps/ml-worker/diagnostics/family_diagnostics.csv` | 1 CSV (108 KB) | Server filesystem / S3 |

These must be added to `.gitignore` immediately. If this is already a git repo, they must also be removed from the index.

---

### MEDIUM — SQL: migrations not in `sql/`

`sql/migrations/` is empty. The 8 migration SQL files are at `apps/ml-worker/jobs/migrations/`. This breaks the intent of having `sql/` as the canonical SQL home.

---

### MEDIUM — infra: systemd units unversioned

The 12 `gh-*.{service,timer}` files are production-deployed at `/etc/systemd/system/` but do not exist anywhere in the monorepo. Any change to them is currently undocumented and unversioned.

---

### MEDIUM — ml-worker: 4 requirements files with no canonical

| File | Size | Contents |
|------|------|---------|
| `requirements.txt` | 1299 bytes | Full pinned set |
| `requirements_clean.txt` | 922 bytes | Cleaned subset |
| `requirements_cloud.lock` | 1124 bytes | Cloud-specific lock |
| `requirements_snapshot.txt` | 1137 bytes | Snapshot at a point in time |

**Resolution:** Choose one (recommend `requirements.txt`) as canonical. Move others to `docs/migration/requirements-history/` or delete.

---

### MEDIUM — infra: unnecessary nesting `infra/scripts/bin/`

The `scripts/` intermediate directory adds no value. All 18 scripts should live at `infra/bin/` directly.

---

### LOW — greenbrain-v2: orphaned workspace

`/opt/greenbrain-v2/` was a staging workspace with:
- `database/current-schema.sql` (26874 lines) — the only canonical full schema, not yet in `sql/schema/`
- `docs/` — 7 discovery docs, already copied to `greenbrain-platform/docs/discovery/`
- `backend/`, `frontend/`, `ml/`, `sandbox/` — all empty or stub

**Resolution:** After migrating `current-schema.sql` to `sql/schema/`, this workspace can be archived.

---

### LOW — `ISTRUZIONI & FUNZIONAMENTO/` folder

Path: `apps/ml-worker/ISTRUZIONI  & FUNZIONAMENTO/` (note: two spaces, special characters)
Contents: `Funzionamento tabella _DENSE.json`, `lovabel .env corretto.json`

Problems: spaces+special chars in dirname, JSON used as documentation format, content duplicates information now in proper markdown docs.

---

## Summary Checklist

```
[ ] Add .gitignore entries: models_v4/, parquet_cache/, priors_cache/, logs/, __pycache__/, *.pyc, *.bak, *_progress.json
[ ] Move sql migrations: apps/ml-worker/jobs/migrations/*.sql → sql/migrations/
[ ] Move schema: greenbrain-v2/database/current-schema.sql → sql/schema/current-schema.sql
[ ] Move shell entry scripts: jobs/run_*.sh, jobs/train_one_safe.sh → apps/ml-worker/scripts/
[ ] Move root-level maintenance scripts → apps/ml-worker/maintenance/
[ ] Move backtest/analysis scripts → apps/ml-worker/analysis/
[ ] Flatten infra: infra/scripts/bin/ → infra/bin/
[ ] Version systemd units: copy /etc/systemd/system/gh-*.{service,timer} → infra/systemd/
[ ] Delete .bak files: config.py.bak, ops.py.bak, gh-audit.bak_*, build_seasonal_priors.py.bak_*
[ ] Mark legacy: train_all_batches.py, fetch_forecast_dataset.py, run_train_all_*.sh, patch_*.py scripts
[ ] Resolve frontend duplicate: diff apps/frontend/src vs /opt/greenbrain/frontend/src
[ ] Fix pg_cron: disable jobids 30, 38, 39 (every-minute pipelines); write canonical sql/cron/pg_cron_canonical.sql
[ ] Consolidate requirements.txt: choose one canonical, remove others
[ ] Convert ISTRUZIONI folder → docs/ markdown, delete folder
[ ] Archive /opt/greenbrain-v2 after schema migration
```
