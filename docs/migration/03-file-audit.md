# File Audit — Classification
> Evidence-based scan of `/opt/greenbrain-platform`. All references verified via grep imports,
> subprocess calls, bin script contents, and systemd ExecStart chains.
> Generated: 2026-03-26

---

## Classification Legend

| Tag | Meaning |
|-----|---------|
| **KEEP** | Active, referenced by scheduler/importer/entrypoint — do not touch |
| **KEEP → MOVE** | Active but wrong location; keep content, relocate |
| **ARCHIVE** | Not active code but has reference/history value; move to `_archive/` or `sql/migrations/` |
| **LEGACY** | Superseded by newer code; keep temporarily for context, then delete |
| **DELETE** | .bak files, runtime data, one-time patches already applied, secret credentials |

---

## ⚠️ SECURITY — Act Immediately

| File | Issue | Action |
|------|-------|--------|
| `apps/ml-worker/ISTRUZIONI  & FUNZIONAMENTO/lovabel .env corretto.json` | **Contains live Supabase credentials** — `VITE_SUPABASE_PROJECT_ID`, full `VITE_SUPABASE_URL`, JWT `VITE_SUPABASE_PUBLISHABLE_KEY` | **DELETE immediately**. If repo has git history, rotate the Supabase anon key. |

---

## ⚠️ MISSING FILE — Referenced But Not Present

| Referenced in | Expected file | Status |
|--------------|--------------|--------|
| `infra/scripts/bin/gh-audit` line 53: `py_compile jobs/ml_monitor_db.py` | `apps/ml-worker/jobs/ml_monitor_db.py` | **Does not exist in repo**. `gh-audit` will fail at this check. Either the file was deleted or was never migrated from `/opt/greenhouse/repo/`. |

---

## apps/ml-worker/ — Root Level

| File | Class | Reason |
|------|-------|--------|
| `__init__.py` | **KEEP** | Python package marker; required for relative imports |
| `data_access_v1.py` | **KEEP** | Imported by `train_v4_single_family_tweedie.py` and `predict_v4_single_family_tweedie.py` |
| `predict_v4_single_family_tweedie.py` | **KEEP** | Core predictor; called as subprocess by `predict_family_router.py`; imports `jobs.seasonality_gate` |
| `train_v4_single_family_tweedie.py` | **KEEP** | Core trainer; called as subprocess by `train_family_router.py` |
| `requirements.txt` | **KEEP** | Canonical pinned requirements — 1299 bytes, most complete |
| `requirements_clean.txt` | **ARCHIVE** | Cleaned subset; no scheduler reference; keep as historical record |
| `requirements_cloud.lock` | **ARCHIVE** | Cloud-specific lock snapshot; historical only |
| `requirements_snapshot.txt` | **ARCHIVE** | Point-in-time snapshot; historical only |
| `backfill_dense_weekly.py` | **KEEP → MOVE** | Manual maintenance tool; no scheduler ref; move to `maintenance/` |
| `backfill_fact_weekly.py` | **KEEP → MOVE** | Manual maintenance tool; move to `maintenance/` |
| `backfill_features_weekly.py` | **KEEP → MOVE** | Manual maintenance tool; move to `maintenance/` |
| `patch_holidays_features_weekly.py` | **KEEP → MOVE** | Manual maintenance tool; move to `maintenance/` |
| `refresh_weekday_strength.py` | **KEEP → MOVE** | Manual maintenance; move to `maintenance/` |
| `sync_holidays.py` | **KEEP → MOVE** | Manual maintenance; move to `maintenance/` |
| `backtest_v4_family_plus_fasce.py` | **KEEP → MOVE** | Valuable backtest; no scheduler ref; move to `analysis/` |
| `backtest_v4_family_total.py` | **KEEP → MOVE** | Valuable backtest; move to `analysis/` |
| `evaluate_v4_forecast.py` | **KEEP → MOVE** | Forecast vs actuals comparison; move to `analysis/` |
| `fetch_forecast_dataset_v2.py` | **KEEP → MOVE** | CSV export utility; move to `analysis/` |
| `fetch_forecast_dataset.py` | **LEGACY** | Superseded by `_v2.py`; uses old `get_engine()` pattern; no scheduler ref |
| `test_spaces.py` | **KEEP → MOVE** | Tests DO Spaces connectivity; move to `tests/` |
| `backfill_features_progress.json` | **DELETE** | Runtime state file; records last processed batch; not source |
| `patch_holidays_progress.json` | **DELETE** | Runtime state file; records last processed batch; not source |

---

## apps/ml-worker/jobs/ — Orchestration Jobs

| File | Class | Reason |
|------|-------|--------|
| `__init__.py` | **KEEP** | Package marker |
| `benchmark_family.py` | **KEEP** | Model benchmarking CLI; referenced in `gh-audit-ops` process scan |
| `diagnose_families.py` | **KEEP** | Demand diagnostics; used manually via CLI |
| `download_priors_from_supabase.py` | **KEEP** | Called step 4 in `run_predict_all.sh` |
| `dump_families.py` | **KEEP** | Utility to list active families; used manually |
| `ensure_model_bundle.py` | **KEEP** | Core infra; imports `scripts.spaces_io`; called by `predict_all.py` and `train_missing_batches.py` |
| `family_resolver.py` | **KEEP** | Imported by `predict_all.py`, `train_missing_batches.py` |
| `ml_ops_bridge.py` | **KEEP** | Core infra; imported by all train/predict orchestrators |
| `model_control.py` | **KEEP** | Governance CLI; called by `gh-train-one` and `gh-train-family` bin scripts |
| `predict_all.py` | **KEEP** | Called by `run_predict_all.sh` (systemd ExecStart via `gh-predict-all`) |
| `predict_family_router.py` | **KEEP** | Called as subprocess by `predict_all.py`; routes to engine |
| `refresh_registry.py` | **KEEP** | Called by `gh-refresh-registry` (systemd ExecStart) |
| `seasonality_gate.py` | **KEEP** | Imported by `predict_v4_single_family_tweedie.py` |
| `sync_local_artifacts.py` | **KEEP** | Called by `gh-sync-local-artifacts` (systemd ExecStartPost) |
| `train_all_monitor.py` | **KEEP** | Called by `gh-train-biweekly-all` and `gh-train-quarterly` systemd services |
| `train_family_router.py` | **KEEP** | Called as subprocess by `train_missing_batches.py` and `train_all_monitor.py` |
| `train_missing_batches.py` | **KEEP** | Called by `run_train_missing.sh` (systemd ExecStart via `gh-train-missing`) |
| `update_family_state.py` | **KEEP** | Manual repair tool; no scheduler ref but essential ops utility |
| `upload_priors_to_supabase.py` | **KEEP** | Called step 3 in `run_predict_all.sh` |
| `validate_engines.py` | **KEEP** | CI/validation; referenced in `gh-audit` via `py_compile` check |
| `train_all_batches.py` | **LEGACY** | Superseded by `train_all_monitor.py`; reads from deprecated `mv_famiglie_catalog` instead of `v_family_execution_routing_v2`; only called by `run_train_all_until_done.sh` (also legacy) |
| `run_predict_all.sh` | **KEEP → MOVE** | systemd ExecStart for `gh-predict-all.service`; move to `scripts/` |
| `run_train_missing.sh` | **KEEP → MOVE** | systemd ExecStart for `gh-train-missing.service`; move to `scripts/` |
| `train_one_safe.sh` | **KEEP → MOVE** | Called by `gh-train-one` bin script; move to `scripts/` |
| `run_train_all_parallel.sh` | **LEGACY** | Requires pre-generated `/opt/greenhouse/tmp/families.txt`; superseded by `train_all_monitor.py` parallel worker pool |
| `run_train_all_until_done.sh` | **LEGACY** | Loop wrapper that calls `train_all_batches.py` (also legacy); superseded by systemd `Persistent=true` + `train_all_monitor.py` |
| `run_train_missing_until_done.sh` | **LEGACY** | Loop wrapper calling `run_train_missing.sh`; superseded by systemd retry logic |
| `seasonality_gate.py` | **KEEP** | Imported by core predictor |

---

## apps/ml-worker/jobs/migrations/ — Applied SQL Migrations

All 8 files are applied migrations. They are **not** referenced by any Python scheduler, but are essential historical record. They belong in `sql/migrations/`, not buried in the Python jobs tree.

| File | Class | Action |
|------|-------|--------|
| `blocco_a_migration.sql` | **ARCHIVE → MOVE** | Move to `sql/migrations/` |
| `blocco_b_migration.sql` | **ARCHIVE → MOVE** | Move to `sql/migrations/` |
| `blocco_c_migration.sql` | **ARCHIVE → MOVE** | Move to `sql/migrations/` |
| `blocco_c1_migration.sql` | **ARCHIVE → MOVE** | Move to `sql/migrations/` |
| `blocco_d_migration.sql` | **ARCHIVE → MOVE** | Move to `sql/migrations/` |
| `blocco_d1_migration.sql` | **ARCHIVE → MOVE** | Move to `sql/migrations/` |
| `blocco_f_migration.sql` | **ARCHIVE → MOVE** | Move to `sql/migrations/` |
| `blocco_g_migration.sql` | **ARCHIVE → MOVE** | Move to `sql/migrations/` |

---

## apps/ml-worker/jobs/engines/ — Model Engines

All active. All imported by `train_family_router.py` and `predict_family_router.py`.

| File | Class |
|------|-------|
| `__init__.py` | **KEEP** |
| `engine_croston.py` | **KEEP** |
| `engine_ets.py` | **KEEP** |
| `engine_naive_zero.py` | **KEEP** |
| `engine_sarima.py` | **KEEP** |
| `engine_seasonal_croston.py` | **KEEP** |
| `engine_tsb.py` | **KEEP** |
| `engine_validation.py` | **KEEP** |
| `fascia_allocator.py` | **KEEP** |
| `forecast_writer.py` | **KEEP** |

---

## apps/ml-worker/jobs/parquet_export/ — Parquet Export Pipeline

All active and referenced by `gh-parquet-export.service`.

| File | Class |
|------|-------|
| `export_features_dense.py` | **KEEP** |
| `check_etl_ready.sh` | **KEEP** |
| `scripts/run_daily_parquet_batches.sh` | **KEEP** |
| `README.md` | **KEEP** |

---

## apps/ml-worker/scripts/ — Utility Scripts

| File | Class | Reason |
|------|-------|--------|
| `__init__.py` | **KEEP** | Required — `ensure_model_bundle.py` does `from scripts.spaces_io import ...` |
| `spaces_io.py` | **KEEP** | **Actively imported** by `jobs/ensure_model_bundle.py`; provides DO Spaces boto3 wrappers |
| `patch_get_engine_urlcreate.py` | **DELETE** | One-time patch already applied to `predict_v4_single_family_tweedie.py`; creates `.bak_*` files as side effect |
| `patch_predict_safe.py` | **DELETE** | One-time patch already applied (replaced `truncate_forecast_table` → `delete_family_window`); creates `.bak_*` files as side effect |

---

## apps/ml-worker/tools/ — Tools

| File | Class | Reason |
|------|-------|--------|
| `build_seasonal_priors.py` | **KEEP** | Called by `run_predict_all.sh` step 2 |
| `build_seasonal_priors.py.bak_20260304_110508` | **DELETE** | Backup created by one of the patch scripts |
| `hurdle_report.py` | **KEEP** | Analysis tool; no scheduler ref but retained as useful |
| `season_gate_helper_v1.txt` | **ARCHIVE** | Scratch notes about seasonality gate implementation; superseded by `seasonality_gate.py` and discovery docs |

---

## apps/ml-worker/ — ISTRUZIONI Folder

| File | Class | Reason |
|------|-------|--------|
| `ISTRUZIONI  & FUNZIONAMENTO/Funzionamento tabella _DENSE.json` | **ARCHIVE** | Contains useful RAW→DENSE pipeline description (7 steps). Content is now superseded by `docs/discovery/03-table-dependency-graph.md`. Extract to markdown, delete original. |
| `ISTRUZIONI  & FUNZIONAMENTO/lovabel .env corretto.json` | **DELETE** | ⚠️ SECURITY: contains live Supabase `PROJECT_ID` + JWT. Delete immediately. |

---

## apps/ml-worker/ — Runtime Data (gitignore + delete from index)

| Path | Items | Class | Reason |
|------|-------|-------|--------|
| `models_v4/` | 1886 `.pkl` | **DELETE from source** | Binary model bundles; DO Spaces is source of truth |
| `parquet_cache/` | 18520 files | **DELETE from source** | Downloaded parquet files; Supabase Storage is source of truth |
| `priors_cache/` | 847 items (incl. `family_slugs.txt`) | **DELETE from source** | Runtime cache; rebuilt at predict time |
| `logs/` | 4 log files (`refresh_weekday_strength.log`, `predict_v3_db_20families_to_v2.log`, `train_missing_v3.log`, `predict_daily.log`) | **DELETE from source** | Runtime logs; server filesystem only |
| `diagnostics/family_diagnostics.csv` | 1 CSV (108 KB) | **DELETE from source** | Runtime output of `diagnose_families.py`; regenerated on demand |
| `__pycache__/` (all 7 dirs + 60 .pyc files) | ~67 items | **DELETE from source** | Python bytecode; add `**/__pycache__/` and `**/*.pyc` to `.gitignore` |

---

## apps/backend/ — Backup Files

| File | Class | Reason |
|------|-------|--------|
| `app/api/v1/ops.py.bak` | **DELETE** | Backup of `ops.py`; identical content; version control supersedes this |
| `app/core/config.py.bak` | **DELETE** | Backup of `config.py`; identical content; version control supersedes this |

---

## apps/frontend/ — Duplicate of Production

`apps/frontend/src/` is **byte-for-byte identical** to `/opt/greenbrain/frontend/src/` (confirmed by diff).

| Concern | Detail |
|---------|--------|
| `supabase/` folder | 0 items in monorepo vs 1 item in production at `/opt/greenbrain/frontend/supabase/` — **check before treating monorepo as source of truth** |
| `bun.lock` / `bun.lockb` / `package-lock.json` | Both lock file formats present — `bun.lock` + `bun.lockb` (bun) and `package-lock.json` (npm); pick one package manager |
| `node_modules/` | Should be in `.gitignore`; contains `flatted/python/__pycache__` — a Python pycache inside a node_modules package |

---

## infra/scripts/bin/ — CLI Scripts

All 18 scripts are **KEEP**, except one backup file.

| File | Class | Reason |
|------|-------|--------|
| `gh-audit` | **KEEP** | Full ops health check (timers, processes, DB, logs) |
| `gh-audit-ops` | **KEEP** | Lighter ops check |
| `gh-monitor` | **KEEP** | Live process monitor |
| `gh-predict-all` | **KEEP** | Trigger `predict_all.py` via systemd |
| `gh-predict-all-now` | **KEEP** | Force immediate predict |
| `gh-predict-all-test` | **KEEP** | Test predict run |
| `gh-predict-family` | **KEEP** | Single family predict |
| `gh-refresh-ml-diag` | **KEEP** | Refresh 9 `ml_diag` materialized views |
| `gh-refresh-registry` | **KEEP** | Run `refresh_registry.py` |
| `gh-sync-local-artifacts` | **KEEP** | Run `sync_local_artifacts.py` |
| `gh-train-all` | **KEEP** | Trigger `train_all_monitor.py` |
| `gh-train-all-now` | **KEEP** | Force immediate train all |
| `gh-train-all-test` | **KEEP** | Test train all |
| `gh-train-biweekly-all` | **KEEP** | Manual trigger for biweekly train |
| `gh-train-family` | **KEEP** | Single family train via router |
| `gh-train-missing` | **KEEP** | Run `run_train_missing.sh` |
| `gh-train-one` | **KEEP** | Single family train via `model_control.py` |
| `gh-audit.bak_20260307_115013` | **DELETE** | Backup of `gh-audit`; created manually |

---

## infra/systemd/current/ — Systemd Units

12 active unit files + 5 backup files. All `.bak*` files are **DELETE**.

| File | Class | Reason |
|------|-------|--------|
| `gh-parquet-export.service` | **KEEP** | Active production service |
| `gh-parquet-export.timer` | **KEEP** | Active production timer |
| `gh-predict-all.service` | **KEEP** | Active production service |
| `gh-predict-all.timer` | **KEEP** | Active production timer |
| `gh-predict-all.timer.bak_20260310_103353` | **DELETE** | Backup — same size (188 bytes) as active timer |
| `gh-predict-all.timer.bak_20260310_103358` | **DELETE** | Backup — identical to above (5 second difference in timestamp) |
| `gh-refresh-registry.service` | **KEEP** | Active production service |
| `gh-refresh-registry.timer` | **KEEP** | Active production timer |
| `gh-train-biweekly-all.service` | **KEEP** | Active production service |
| `gh-train-biweekly-all.timer` | **KEEP** | Active production timer |
| `gh-train-missing.service` | **KEEP** | Active production service |
| `gh-train-missing.timer` | **KEEP** | Active production timer |
| `gh-train-missing.timer.bak_20260310_103347` | **DELETE** | Backup — same size (207 bytes) as active timer |
| `gh-train-missing.timer.bak_20260310_103358` | **DELETE** | Backup — identical to above |
| `gh-train-quarterly.service` | **KEEP** | Active production service |
| `gh-train-quarterly.service.bak.20260306_131008` | **DELETE** | Backup — 513 bytes vs active 715 bytes; was smaller/older version |
| `gh-train-quarterly.timer` | **KEEP** | Active production timer |

---

## Summary by Classification

### KEEP (no action needed — 67 files)
All active engine files, core Python jobs, systemd units, bin scripts, entry shell scripts, main `requirements.txt`.

### KEEP → MOVE (13 files — change location, not content)

| Current path | Proposed path |
|-------------|--------------|
| `apps/ml-worker/backfill_dense_weekly.py` | `apps/ml-worker/maintenance/` |
| `apps/ml-worker/backfill_fact_weekly.py` | `apps/ml-worker/maintenance/` |
| `apps/ml-worker/backfill_features_weekly.py` | `apps/ml-worker/maintenance/` |
| `apps/ml-worker/patch_holidays_features_weekly.py` | `apps/ml-worker/maintenance/` |
| `apps/ml-worker/refresh_weekday_strength.py` | `apps/ml-worker/maintenance/` |
| `apps/ml-worker/sync_holidays.py` | `apps/ml-worker/maintenance/` |
| `apps/ml-worker/backtest_v4_family_plus_fasce.py` | `apps/ml-worker/analysis/` |
| `apps/ml-worker/backtest_v4_family_total.py` | `apps/ml-worker/analysis/` |
| `apps/ml-worker/evaluate_v4_forecast.py` | `apps/ml-worker/analysis/` |
| `apps/ml-worker/fetch_forecast_dataset_v2.py` | `apps/ml-worker/analysis/` |
| `apps/ml-worker/test_spaces.py` | `apps/ml-worker/tests/` |
| `apps/ml-worker/jobs/run_predict_all.sh` | `apps/ml-worker/scripts/` |
| `apps/ml-worker/jobs/run_train_missing.sh` | `apps/ml-worker/scripts/` |
| `apps/ml-worker/jobs/train_one_safe.sh` | `apps/ml-worker/scripts/` |
| `apps/ml-worker/jobs/migrations/*.sql` (8 files) | `sql/migrations/` |

### ARCHIVE (8 files — keep for reference, move out of active tree)

| File | Note |
|------|------|
| `apps/ml-worker/requirements_clean.txt` | Historical cleaned subset |
| `apps/ml-worker/requirements_cloud.lock` | Historical cloud lock |
| `apps/ml-worker/requirements_snapshot.txt` | Historical snapshot |
| `apps/ml-worker/tools/season_gate_helper_v1.txt` | Scratch notes on seasonality gate |
| `apps/ml-worker/ISTRUZIONI  & FUNZIONAMENTO/Funzionamento tabella _DENSE.json` | Useful pipeline description; extract content to markdown then delete |

### LEGACY (5 files — superseded, keep temporarily for context)

| File | Superseded by |
|------|--------------|
| `apps/ml-worker/jobs/train_all_batches.py` | `train_all_monitor.py` (uses `v_family_execution_routing_v2`, mlops bridge, 4-parallel) |
| `apps/ml-worker/jobs/run_train_all_parallel.sh` | `train_all_monitor.py` (no longer needs pre-generated families list) |
| `apps/ml-worker/jobs/run_train_all_until_done.sh` | `train_all_monitor.py` + systemd `Persistent=true` |
| `apps/ml-worker/jobs/run_train_missing_until_done.sh` | systemd `Persistent=true` + retry logic in `train_missing_batches.py` |
| `apps/ml-worker/fetch_forecast_dataset.py` | `fetch_forecast_dataset_v2.py` |

### DELETE (24 items)

| File | Reason |
|------|--------|
| `apps/ml-worker/ISTRUZIONI  & FUNZIONAMENTO/lovabel .env corretto.json` | ⚠️ Live Supabase credentials |
| `apps/ml-worker/backfill_features_progress.json` | Runtime state |
| `apps/ml-worker/patch_holidays_progress.json` | Runtime state |
| `apps/ml-worker/tools/build_seasonal_priors.py.bak_20260304_110508` | Backup file |
| `apps/ml-worker/scripts/patch_get_engine_urlcreate.py` | One-time patch, already applied |
| `apps/ml-worker/scripts/patch_predict_safe.py` | One-time patch, already applied |
| `apps/backend/app/api/v1/ops.py.bak` | Backup file |
| `apps/backend/app/core/config.py.bak` | Backup file |
| `infra/scripts/bin/gh-audit.bak_20260307_115013` | Backup file |
| `infra/systemd/current/gh-predict-all.timer.bak_20260310_103353` | Backup file (identical to active) |
| `infra/systemd/current/gh-predict-all.timer.bak_20260310_103358` | Backup file (duplicate of above) |
| `infra/systemd/current/gh-train-missing.timer.bak_20260310_103347` | Backup file |
| `infra/systemd/current/gh-train-missing.timer.bak_20260310_103358` | Backup file (duplicate) |
| `infra/systemd/current/gh-train-quarterly.service.bak.20260306_131008` | Backup of older version (513 bytes vs 715 bytes active) |
| `apps/ml-worker/models_v4/` (1886 items) | Runtime data — not source |
| `apps/ml-worker/parquet_cache/` (18520 items) | Runtime data — not source |
| `apps/ml-worker/priors_cache/` (847 items) | Runtime data — not source |
| `apps/ml-worker/logs/` (4 log files) | Runtime logs |
| `apps/ml-worker/diagnostics/family_diagnostics.csv` | Runtime output |
| All `__pycache__/` dirs (12 dirs, 60 .pyc files) | Python bytecode — gitignore |

---

## Proposed .gitignore Additions

```gitignore
# Runtime data
apps/ml-worker/models_v4/
apps/ml-worker/parquet_cache/
apps/ml-worker/priors_cache/
apps/ml-worker/logs/
apps/ml-worker/diagnostics/*.csv
apps/ml-worker/*_progress.json

# Python bytecode
**/__pycache__/
**/*.pyc
**/*.pyo

# Node
apps/frontend/node_modules/

# Backup files
**/*.bak
**/*.bak_*
**/*.bak.*

# Secrets / env
.env
.env.*
!.env.example
```

---

## Action Priority

| Priority | Action |
|----------|--------|
| **P0 — Now** | Delete `lovabel .env corretto.json` (live credentials) |
| **P0 — Now** | Add `models_v4/`, `parquet_cache/`, `priors_cache/` to `.gitignore` and remove from git index |
| **P1 — Next** | Delete all 9 `.bak` files |
| **P1 — Next** | Delete both `patch_*.py` scripts (one-time patches already applied) |
| **P1 — Next** | Delete `backfill_features_progress.json` and `patch_holidays_progress.json` |
| **P2 — This week** | Move 8 SQL migrations to `sql/migrations/` |
| **P2 — This week** | Move shell entry scripts out of `jobs/` into `scripts/` |
| **P2 — This week** | Move root-level maintenance/analysis/test scripts to their groups |
| **P3 — Before next release** | Mark `train_all_batches.py` and 3 legacy shell scripts as deprecated |
| **P3 — Before next release** | Investigate missing `jobs/ml_monitor_db.py` (referenced in `gh-audit`) |
| **P3 — Before next release** | Consolidate requirements files to single canonical |
| **P4 — Cleanup** | Flatten `infra/scripts/bin/` → `infra/bin/` |
| **P4 — Cleanup** | Convert `ISTRUZIONI` JSON to markdown, delete folder |
