# Wave 3 Runbook
> ML runtime path migration. All 6 services execute Python from monorepo after this wave.
> Generated: 2026-03-27.

---

## 1. Objective

Update `GH_REPO_DIR` to the monorepo path. Fix 3 shell scripts to use it instead of hardcoded `/opt/greenhouse/repo`. Change `WorkingDirectory` in biweekly and quarterly unit files. Test each service one at a time before freezing the legacy repo.

**What is NOT changed here:**
- Venv stays at `/opt/greenhouse/venv/` — no change
- Logs stay at `/opt/greenhouse/logs/` — no change
- `.bak_phase*` files are not applied — they are already the live monorepo versions (see §3 Step 2)
- No Docker changes
- No storage abstraction changes (already live in monorepo — see §3 Step 2)

---

## 2. Preconditions

```bash
# Wave 2 must be complete:
grep "EnvironmentFile" /etc/systemd/system/gh-train-biweekly-all.service
grep "EnvironmentFile" /etc/systemd/system/gh-train-quarterly.service
# Expected: no output for both

# load_env.sh must be working:
export APP_ENV=dev
source /opt/greenbrain-platform/infra/scripts/load_env.sh
echo $GH_REPO_DIR
# Expected: /opt/greenhouse/repo  (Wave 2 value — will be updated in Step 3)

echo $STORAGE_BACKEND
# Expected: supabase  ← MUST be supabase before switching execution path

# No ML job must be running right now:
systemctl is-active gh-predict-all gh-train-missing gh-parquet-export \
  gh-train-biweekly-all gh-train-quarterly 2>/dev/null
# Expected: all show "inactive"
```

---

## 3. Step-by-step commands

---

### Step 1 — Verify Wave 2 complete

```bash
for svc in gh-train-biweekly-all gh-train-quarterly; do
  echo "=== $svc ===" 
  grep "EnvironmentFile\|WorkingDirectory\|APP_ENV" /etc/systemd/system/${svc}.service
done
```

**Expected:**
```
=== gh-train-biweekly-all ===
Environment=APP_ENV=dev
WorkingDirectory=/opt/greenhouse/repo
=== gh-train-quarterly ===
Environment=APP_ENV=dev
WorkingDirectory=/opt/greenhouse/repo
```

No `EnvironmentFile=` line. If it is present, Wave 2 is not complete — stop.

---

### Step 2 — Diff legacy repo vs monorepo Python files

**Purpose:** Understand which files differ before switching execution path. Some files already have Wave 4 storage abstraction in the monorepo — this is expected and documented.

```bash
MONO=/opt/greenbrain-platform/apps/ml-worker
LEGACY=/opt/greenhouse/repo

echo "--- train_all_monitor.py ---"
diff "$LEGACY/jobs/train_all_monitor.py" "$MONO/jobs/train_all_monitor.py" \
  && echo "IDENTICAL" || echo "DIFFERS"

echo "--- train_missing_batches.py ---"
diff "$LEGACY/jobs/train_missing_batches.py" "$MONO/jobs/train_missing_batches.py" \
  && echo "IDENTICAL" || echo "DIFFERS"

echo "--- predict_all.py ---"
diff "$LEGACY/jobs/predict_all.py" "$MONO/jobs/predict_all.py" \
  && echo "IDENTICAL" || echo "DIFFERS"

echo "--- data_access_v1.py ---"
diff "$LEGACY/data_access_v1.py" "$MONO/data_access_v1.py" \
  && echo "IDENTICAL" || echo "DIFFERS — storage abstraction already live"

echo "--- export_features_dense.py ---"
diff "$LEGACY/jobs/parquet_export/export_features_dense.py" \
     "$MONO/jobs/parquet_export/export_features_dense.py" \
  && echo "IDENTICAL" || echo "DIFFERS — storage abstraction already live"

echo "--- upload_priors_to_supabase.py ---"
diff "$LEGACY/jobs/upload_priors_to_supabase.py" \
     "$MONO/jobs/upload_priors_to_supabase.py" \
  && echo "IDENTICAL" || echo "DIFFERS — storage abstraction already live"

echo "--- download_priors_from_supabase.py ---"
diff "$LEGACY/jobs/download_priors_from_supabase.py" \
     "$MONO/jobs/download_priors_from_supabase.py" \
  && echo "IDENTICAL" || echo "DIFFERS — storage abstraction already live"
```

**Expected output (as of 2026-03-27):**
```
--- train_all_monitor.py --- IDENTICAL
--- train_missing_batches.py --- IDENTICAL
--- predict_all.py --- IDENTICAL
--- data_access_v1.py --- DIFFERS — storage abstraction already live
--- export_features_dense.py --- DIFFERS — storage abstraction already live
--- upload_priors_to_supabase.py --- DIFFERS — storage abstraction already live
--- download_priors_from_supabase.py --- DIFFERS — storage abstraction already live
```

⚠️ **The 4 "DIFFERS" files have the Wave 4 storage abstraction already applied in the monorepo.** Switching execution to the monorepo means this code runs immediately. This is safe because `STORAGE_BACKEND=supabase` routes through the same Supabase API calls as the legacy SDK code.

**If any of the 3 "IDENTICAL" files show DIFFERS:** Stop. Investigate what changed before proceeding.

**If `STORAGE_BACKEND` is not `supabase`:** Stop. Running the monorepo storage-abstracted code with a non-supabase backend against production is unsafe.

```bash
source /opt/greenbrain-platform/infra/scripts/load_env.sh
echo $STORAGE_BACKEND   # Must be: supabase
```

---

### Step 3 — Update GH_REPO_DIR in dev.env

**Purpose:** Change the `GH_REPO_DIR` pointer from the legacy repo to the monorepo. This is the single variable that all 3 shell scripts will read after the next steps.

```bash
# Confirm current value:
grep "^GH_REPO_DIR=" /opt/greenbrain-platform/infra/env/dev.env
# Expected: GH_REPO_DIR=/opt/greenhouse/repo

# Update:
sed -i 's|^GH_REPO_DIR=.*|GH_REPO_DIR=/opt/greenbrain-platform/apps/ml-worker|' \
  /opt/greenbrain-platform/infra/env/dev.env

# Verify:
grep "^GH_REPO_DIR=" /opt/greenbrain-platform/infra/env/dev.env
# Expected: GH_REPO_DIR=/opt/greenbrain-platform/apps/ml-worker
```

**Rollback:**
```bash
sed -i 's|^GH_REPO_DIR=.*|GH_REPO_DIR=/opt/greenhouse/repo|' \
  /opt/greenbrain-platform/infra/env/dev.env
```

---

### Step 4 — Update run_train_missing.sh

**Purpose:** Script hardcodes `REPO_DIR="${BASE_DIR}/repo"` (resolves to `/opt/greenhouse/repo`). Change it to use `GH_REPO_DIR`. The venv and log paths stay at the legacy location.

```bash
SCRIPT=/opt/greenbrain-platform/apps/ml-worker/jobs/run_train_missing.sh

# Confirm current line:
grep "REPO_DIR=" "$SCRIPT"
# Expected: REPO_DIR="${BASE_DIR}/repo"

# Replace:
sed -i 's|REPO_DIR="${BASE_DIR}/repo"|REPO_DIR="${GH_REPO_DIR:-${BASE_DIR}/repo}"|' \
  "$SCRIPT"

# Verify:
grep "REPO_DIR=" "$SCRIPT"
# Expected: REPO_DIR="${GH_REPO_DIR:-${BASE_DIR}/repo}"
```

**Rollback:**
```bash
sed -i 's|REPO_DIR="${GH_REPO_DIR:-${BASE_DIR}/repo}"|REPO_DIR="${BASE_DIR}/repo"|' \
  /opt/greenbrain-platform/apps/ml-worker/jobs/run_train_missing.sh
```

---

### Step 5 — Update run_predict_all.sh

**Purpose:** Script hardcodes `REPO_DIR="/opt/greenhouse/repo"` and a `GIT_SHA` path. Both must be updated to use `GH_REPO_DIR`.

```bash
SCRIPT=/opt/greenbrain-platform/apps/ml-worker/jobs/run_predict_all.sh

# Confirm current lines:
grep 'REPO_DIR=\|cd /opt/greenhouse/repo' "$SCRIPT"
# Expected:
#   REPO_DIR="/opt/greenhouse/repo"
#   GIT_SHA="$(cd /opt/greenhouse/repo && git rev-parse ..."

# Fix REPO_DIR:
sed -i 's|REPO_DIR="/opt/greenhouse/repo"|REPO_DIR="${GH_REPO_DIR:-/opt/greenhouse/repo}"|' \
  "$SCRIPT"

# Fix GIT_SHA inline cd:
sed -i 's|cd /opt/greenhouse/repo && git rev-parse|cd "${GH_REPO_DIR}" \&\& git rev-parse|g' \
  "$SCRIPT"

# Verify:
grep 'REPO_DIR=\|GIT_SHA=' "$SCRIPT"
# Expected:
#   REPO_DIR="${GH_REPO_DIR:-/opt/greenhouse/repo}"
#   GIT_SHA="$(cd "${GH_REPO_DIR}" && git rev-parse --short HEAD 2>/dev/null || true)"
```

**Rollback:**
```bash
SCRIPT=/opt/greenbrain-platform/apps/ml-worker/jobs/run_predict_all.sh
sed -i 's|REPO_DIR="${GH_REPO_DIR:-/opt/greenhouse/repo}"|REPO_DIR="/opt/greenhouse/repo"|' "$SCRIPT"
sed -i 's|cd "${GH_REPO_DIR}" \&\& git rev-parse|cd /opt/greenhouse/repo \&\& git rev-parse|g' "$SCRIPT"
```

---

### Step 6 — Update run_daily_parquet_batches.sh

**Purpose:** Script hardcodes `PROJECT_DIR="/opt/greenhouse/repo/jobs/parquet_export"`. Change it to use `GH_REPO_DIR`. The log directory stays in the legacy location.

```bash
SCRIPT=/opt/greenbrain-platform/apps/ml-worker/jobs/parquet_export/scripts/run_daily_parquet_batches.sh

# Confirm current line:
grep "^PROJECT_DIR=" "$SCRIPT"
# Expected: PROJECT_DIR="/opt/greenhouse/repo/jobs/parquet_export"

# Replace:
sed -i 's|PROJECT_DIR="/opt/greenhouse/repo/jobs/parquet_export"|PROJECT_DIR="${GH_REPO_DIR:-/opt/greenhouse/repo}/jobs/parquet_export"|' \
  "$SCRIPT"

# Verify:
grep "^PROJECT_DIR=" "$SCRIPT"
# Expected: PROJECT_DIR="${GH_REPO_DIR:-/opt/greenhouse/repo}/jobs/parquet_export"
```

**Rollback:**
```bash
sed -i 's|PROJECT_DIR="${GH_REPO_DIR:-/opt/greenhouse/repo}/jobs/parquet_export"|PROJECT_DIR="/opt/greenhouse/repo/jobs/parquet_export"|' \
  /opt/greenbrain-platform/apps/ml-worker/jobs/parquet_export/scripts/run_daily_parquet_batches.sh
```

---

### Step 7 — Verify no hardcoded /opt/greenhouse/repo in the 3 scripts

```bash
for f in \
  /opt/greenbrain-platform/apps/ml-worker/jobs/run_train_missing.sh \
  /opt/greenbrain-platform/apps/ml-worker/jobs/run_predict_all.sh \
  /opt/greenbrain-platform/apps/ml-worker/jobs/parquet_export/scripts/run_daily_parquet_batches.sh; do
  echo "=== $(basename $f) ==="
  grep "/opt/greenhouse/repo" "$f" || echo "  CLEAN"
done
```

**Expected:** All 3 show `CLEAN`. No remaining hardcoded path.

**If any file still shows the legacy path:** Re-run the corresponding step above. Do not proceed until all 3 are clean.

---

### Step 8 — Update gh-train-biweekly-all.service WorkingDirectory

**Purpose:** Change `WorkingDirectory` from legacy repo to monorepo. `ExecStart` uses a relative Python path (`jobs/train_all_monitor.py`) so it will now resolve against the monorepo. `load_env.sh` is already in ExecStart from Wave 2.

```bash
# Confirm current WorkingDirectory:
grep "WorkingDirectory" /etc/systemd/system/gh-train-biweekly-all.service
# Expected: WorkingDirectory=/opt/greenhouse/repo

# Back up:
cp /etc/systemd/system/gh-train-biweekly-all.service \
   /opt/greenbrain-platform/infra/systemd/gh-train-biweekly-all.service.bak_wave3

# Update:
sed -i 's|WorkingDirectory=/opt/greenhouse/repo|WorkingDirectory=/opt/greenbrain-platform/apps/ml-worker|' \
  /etc/systemd/system/gh-train-biweekly-all.service

# Verify:
grep "WorkingDirectory" /etc/systemd/system/gh-train-biweekly-all.service
# Expected: WorkingDirectory=/opt/greenbrain-platform/apps/ml-worker
```

**Rollback:**
```bash
cp /opt/greenbrain-platform/infra/systemd/gh-train-biweekly-all.service.bak_wave3 \
   /etc/systemd/system/gh-train-biweekly-all.service
systemctl daemon-reload
```

---

### Step 9 — Update gh-train-quarterly.service WorkingDirectory and ExecStart

**Purpose:** Change `WorkingDirectory`. Quarterly's `ExecStart` uses an absolute path to the Python script (`/opt/greenhouse/repo/jobs/train_all_monitor.py`) — update it to a relative path now that `WorkingDirectory` is correct. Also update the inline `GIT_SHA` git command.

```bash
# Confirm current state:
grep "WorkingDirectory\|train_all_monitor\|GIT_SHA" \
  /etc/systemd/system/gh-train-quarterly.service
# Expected:
#   WorkingDirectory=/opt/greenhouse/repo
#   ...python3 -u /opt/greenhouse/repo/jobs/train_all_monitor.py...
#   ...cd /opt/greenhouse/repo && git rev-parse...

# Back up:
cp /etc/systemd/system/gh-train-quarterly.service \
   /opt/greenbrain-platform/infra/systemd/gh-train-quarterly.service.bak_wave3

# Write the updated unit file in full (3 changes combined):
cat > /etc/systemd/system/gh-train-quarterly.service << 'UNIT'
[Unit]
Description=Greenhouse - Train ALL Families (quarterly)
After=network-online.target
Wants=network-online.target

[Service]
Environment=APP_ENV=dev
Type=oneshot
User=gh
Group=gh
WorkingDirectory=/opt/greenbrain-platform/apps/ml-worker
ExecStart=/bin/bash -lc 'source /opt/greenbrain-platform/infra/scripts/load_env.sh && source /opt/greenhouse/venv/bin/activate && export RUN_TRIGGER_SOURCE=systemd_timer && export GIT_SHA="$(cd "${GH_REPO_DIR}" && git rev-parse --short HEAD 2>/dev/null || true)" && python3 -u jobs/train_all_monitor.py'
TimeoutStartSec=0
ExecStartPost=/bin/bash -lc 'source /opt/greenhouse/venv/bin/activate && cd /opt/greenbrain-platform/apps/ml-worker && /opt/greenbrain-platform/infra/scripts/bin/gh-sync-local-artifacts'
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=6
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

# Verify all 3 changes:
grep "WorkingDirectory" /etc/systemd/system/gh-train-quarterly.service
# Expected: WorkingDirectory=/opt/greenbrain-platform/apps/ml-worker

grep "greenhouse/repo" /etc/systemd/system/gh-train-quarterly.service
# Expected: no output (all legacy paths removed)
```

**Rollback:**
```bash
cp /opt/greenbrain-platform/infra/systemd/gh-train-quarterly.service.bak_wave3 \
   /etc/systemd/system/gh-train-quarterly.service
systemctl daemon-reload
```

---

### Step 10 — daemon-reload

```bash
systemctl daemon-reload

# Confirm units parsed:
systemctl show gh-train-biweekly-all --property=WorkingDirectory
# Expected: WorkingDirectory=/opt/greenbrain-platform/apps/ml-worker

systemctl show gh-train-quarterly --property=WorkingDirectory
# Expected: WorkingDirectory=/opt/greenbrain-platform/apps/ml-worker

systemctl list-timers --all | grep gh- | wc -l
# Expected: 6
```

---

### Step 11 — Smoke test gh-train-missing

**Purpose:** Quickest test — runs in ~2 seconds (0 families need training in normal state). Validates that env load and Python import work from the monorepo path.

```bash
systemctl start gh-train-missing
journalctl -u gh-train-missing -n 20 --no-pager
```

**Expected log output:**
```
[ENV] loaded base.env + dev.env
[ENV] DATABASE_URL ready
START ...
DONE train_missing ... | trained=0 | ok=0 | bad=0 | rc=0
END   ...
OK sync_local_artifacts | processed=...
```

Exit status: `inactive (dead)` with `status=0/SUCCESS`.

**If `ModuleNotFoundError`:** Python cannot find a module from the monorepo path. Run:
```bash
cd /opt/greenbrain-platform/apps/ml-worker
source /opt/greenhouse/venv/bin/activate
python -c "import jobs.train_missing_batches; print('OK')"
```
Identify the missing module and fix `PYTHONPATH` or verify the module exists in the monorepo.

**If `[ENV][ERROR] invalid PG_HOST`:** dev.env is broken. Check Wave 2 step 2 completeness.

**Rollback if test fails:** Revert Step 3 (GH_REPO_DIR) — the service will continue to work from the legacy path since scripts fall back to `${BASE_DIR}/repo` if `GH_REPO_DIR` is not set correctly.

---

### Step 12 — Smoke test gh-predict-all with PREDICT_LIMIT=1

**Purpose:** Tests the full predict pipeline (priors build → Supabase upload → predict → DB write) for one family. Validates that storage-abstracted `data_access_v1.py` and `upload/download_priors` work correctly from the monorepo.

```bash
# Capture one baseline forecast row before the test:
source /opt/greenbrain-platform/infra/scripts/load_env.sh
SLUG=$(psql "$DATABASE_URL" -Atc \
  "SELECT famiglia_slug FROM famiglie_catalog_static LIMIT 1;")
echo "Test slug: $SLUG"

psql "$DATABASE_URL" -c "
  SELECT famiglia_slug, forecast_date, q50
  FROM greenhouse_forecast_results_v2
  WHERE famiglia_slug = '$SLUG'
  ORDER BY forecast_date DESC LIMIT 5;" > /tmp/before_predict.txt

# Run with limit:
PREDICT_LIMIT=1 systemctl start gh-predict-all

# Wait — takes ~2 min for 1 family:
journalctl -u gh-predict-all -n 40 --no-pager
```

**Expected log output:**
```
[ENV] loaded base.env + dev.env
[ENV] DATABASE_URL ready
PRIORS_START ...
OK update supabase://ml-snapshots/priors/...
OK download supabase://ml-snapshots/priors/...
PRIORS_END ...
START ...
DONE predict_all -> ... | ok=1 bad=0 rc=0
END   ...
```

Exit status: `status=0/SUCCESS`.

```bash
# Verify a new forecast row exists:
psql "$DATABASE_URL" -c "
  SELECT famiglia_slug, MAX(created_at) as last_predict
  FROM greenhouse_forecast_results_v2
  WHERE famiglia_slug = '$SLUG'
  GROUP BY famiglia_slug;" > /tmp/after_predict.txt

diff /tmp/before_predict.txt /tmp/after_predict.txt
# A new row should be present (different timestamp)
```

**If `storage backend` errors in logs:** Check `STORAGE_BACKEND` is set to `supabase`:
```bash
source /opt/greenbrain-platform/infra/scripts/load_env.sh && echo $STORAGE_BACKEND
```

**If `bad=1` or non-zero exit:** Check the log file referenced in `DONE predict_all -> /opt/greenhouse/logs/predict_all_*.log`. The storage-abstracted priors code must succeed for predict to work.

**Rollback:** Revert `GH_REPO_DIR` to `/opt/greenhouse/repo` (Step 3 rollback) and revert the 3 scripts (Steps 4–6 rollbacks).

---

### Step 13 — Smoke test gh-parquet-export

**Purpose:** Validates parquet export runs `export_features_dense.py` from the monorepo path with the storage abstraction.

```bash
# Check ETL gate first — parquet export will not run if today's ETL hasn't completed:
source /opt/greenbrain-platform/infra/scripts/load_env.sh
psql "$DATABASE_URL" -Atc "
  SELECT COUNT(*) FROM etl.t_etl_runs
  WHERE run_date = CURRENT_DATE AND status = 'success';"
```

**If count is 0:** The ETL gate will block the export — this is correct behavior. The timer will run at 21:35 CET after ETL completes. To test the export script path without waiting, run it directly:
```bash
ONLY_FAMILY_SLUG=rosa BATCH_SIZE=5 \
  bash /opt/greenbrain-platform/apps/ml-worker/jobs/parquet_export/scripts/run_daily_parquet_batches.sh
journalctl -u gh-parquet-export -n 20 --no-pager || \
  tail -20 /opt/greenhouse/logs/parquet_export/daily_*.log 2>/dev/null | tail -20
```

**If count > 0:** Start the service normally:
```bash
systemctl start gh-parquet-export
journalctl -u gh-parquet-export -n 30 --no-pager
```

**Expected:**
```
PROJECT_DIR=/opt/greenbrain-platform/apps/ml-worker/jobs/parquet_export
...
[RUN ...] progress=...
SUCCESS run_id=... files=... rows=...
```

The `PROJECT_DIR=` log line confirms the monorepo path is being used.

**If `ModuleNotFoundError: No module named 'storage'`:** The venv does not have `storage.backend`. The storage module must be on the Python path. Check:
```bash
cd /opt/greenbrain-platform/apps/ml-worker
source /opt/greenhouse/venv/bin/activate
python -c "from storage.backend import get_storage_backend; print('OK')"
```
If this fails, the `storage/` package in the monorepo is not importable from the venv. Fix: ensure `PYTHONPATH` includes the monorepo root, or install the package into the venv.

---

### Step 14 — Smoke test gh-train-biweekly-all (stop after env confirmation)

**Purpose:** Confirm the service loads env and starts correctly from the monorepo `WorkingDirectory`. Do not wait for a full train cycle (would take hours).

```bash
# Start it:
systemctl start gh-train-biweekly-all &
BG_PID=$!

# Watch logs for the env load confirmation (first ~10 seconds):
sleep 8
journalctl -u gh-train-biweekly-all -n 15 --no-pager
```

**Expected in the first 10 seconds of logs:**
```
[ENV] loaded base.env + dev.env
[ENV] DATABASE_URL ready
START ...
```

**As soon as you see `[ENV] loaded base.env + dev.env`, the env is working.** You may then stop the service:
```bash
systemctl stop gh-train-biweekly-all
```

This will interrupt the training run. That is expected and safe — `train_all_monitor.py` handles `SIGTERM` gracefully.

**If the service exits immediately with error:** Check logs:
```bash
journalctl -u gh-train-biweekly-all -n 30 --no-pager
```
Look for `ModuleNotFoundError` or `[ENV][ERROR]`. If Python import fails, check that `jobs/train_all_monitor.py` exists at the monorepo path and that `PYTHONPATH` is correct.

**Do not wait for training to complete.** The biweekly service trains all 844 families and would run for several hours.

---

### Step 15 — Copy updated unit files to infra/systemd/

```bash
cp /etc/systemd/system/gh-train-biweekly-all.service \
   /opt/greenbrain-platform/infra/systemd/gh-train-biweekly-all.service

cp /etc/systemd/system/gh-train-quarterly.service \
   /opt/greenbrain-platform/infra/systemd/gh-train-quarterly.service

# Verify no legacy paths in the monorepo copies:
grep "greenhouse/repo" \
  /opt/greenbrain-platform/infra/systemd/gh-train-biweekly-all.service \
  /opt/greenbrain-platform/infra/systemd/gh-train-quarterly.service
# Expected: no output
```

---

### Step 16 — Freeze /opt/greenhouse/repo read-only

**Purpose:** Prevent accidental writes to the legacy repo. Do this only after all 4 smoke tests pass.

```bash
# Confirm all 4 smoke tests passed before running this:
# - Step 11: gh-train-missing exit 0 ✓
# - Step 12: gh-predict-all PREDICT_LIMIT=1 ok=1 bad=0 ✓
# - Step 13: gh-parquet-export PROJECT_DIR confirmed ✓
# - Step 14: gh-train-biweekly-all [ENV] loaded confirmed ✓

chmod -R a-w /opt/greenhouse/repo/

# Verify:
touch /opt/greenhouse/repo/test_write 2>&1 | grep -q "Permission denied" \
  && echo "OK: repo is read-only" \
  || echo "FAIL: repo is still writable"
```

**Rollback (restore write access if needed):**
```bash
chmod -R u+w /opt/greenhouse/repo/
```

---

## 4. Validation

Run all checks after completing all steps.

```bash
source /opt/greenbrain-platform/infra/scripts/load_env.sh

echo "=== GH_REPO_DIR ==="
echo $GH_REPO_DIR
# Expected: /opt/greenbrain-platform/apps/ml-worker

echo "=== Shell scripts clean ==="
for f in \
  /opt/greenbrain-platform/apps/ml-worker/jobs/run_train_missing.sh \
  /opt/greenbrain-platform/apps/ml-worker/jobs/run_predict_all.sh \
  /opt/greenbrain-platform/apps/ml-worker/jobs/parquet_export/scripts/run_daily_parquet_batches.sh; do
  count=$(grep -c "/opt/greenhouse/repo" "$f" 2>/dev/null || echo 0)
  echo "$count hardcoded paths in $(basename $f)"
done
# Expected: 0 for all 3

echo "=== WorkingDirectory ==="
grep "WorkingDirectory" /etc/systemd/system/gh-train-biweekly-all.service
grep "WorkingDirectory" /etc/systemd/system/gh-train-quarterly.service
# Expected: /opt/greenbrain-platform/apps/ml-worker for both

echo "=== No greenhouse/repo in live unit files ==="
grep "greenhouse/repo" /etc/systemd/system/gh-train-biweekly-all.service \
  && echo "FAIL" || echo "OK: biweekly clean"
grep "greenhouse/repo" /etc/systemd/system/gh-train-quarterly.service \
  && echo "FAIL" || echo "OK: quarterly clean"

echo "=== Legacy repo read-only ==="
touch /opt/greenhouse/repo/test_wave3 2>&1 | grep -q "Permission denied" \
  && echo "OK: read-only" || echo "FAIL: still writable"

echo "=== All timers still active ==="
systemctl list-timers --all | grep gh- | wc -l
# Expected: 6

echo "=== DB: recent predict run from today ==="
psql "$DATABASE_URL" -c "
  SELECT job_type, status, started_at, rows_processed
  FROM ml_ops.pipeline_run_log_v1
  WHERE started_at > NOW() - INTERVAL '2 hours'
  ORDER BY started_at DESC LIMIT 5;"
# Expected: at least one predict_daily row with status=success and rows_processed=1
```

---

## 5. Rollback

All rollbacks are independent — apply only what failed.

### Rollback GH_REPO_DIR (Step 3):
```bash
sed -i 's|^GH_REPO_DIR=.*|GH_REPO_DIR=/opt/greenhouse/repo|' \
  /opt/greenbrain-platform/infra/env/dev.env
```

### Rollback run_train_missing.sh (Step 4):
```bash
sed -i 's|REPO_DIR="${GH_REPO_DIR:-${BASE_DIR}/repo}"|REPO_DIR="${BASE_DIR}/repo"|' \
  /opt/greenbrain-platform/apps/ml-worker/jobs/run_train_missing.sh
```

### Rollback run_predict_all.sh (Step 5):
```bash
SCRIPT=/opt/greenbrain-platform/apps/ml-worker/jobs/run_predict_all.sh
sed -i 's|REPO_DIR="${GH_REPO_DIR:-/opt/greenhouse/repo}"|REPO_DIR="/opt/greenhouse/repo"|' "$SCRIPT"
sed -i 's|cd "${GH_REPO_DIR}" \&\& git rev-parse|cd /opt/greenhouse/repo \&\& git rev-parse|g' "$SCRIPT"
```

### Rollback run_daily_parquet_batches.sh (Step 6):
```bash
sed -i 's|PROJECT_DIR="${GH_REPO_DIR:-/opt/greenhouse/repo}/jobs/parquet_export"|PROJECT_DIR="/opt/greenhouse/repo/jobs/parquet_export"|' \
  /opt/greenbrain-platform/apps/ml-worker/jobs/parquet_export/scripts/run_daily_parquet_batches.sh
```

### Rollback biweekly unit (Step 8):
```bash
cp /opt/greenbrain-platform/infra/systemd/gh-train-biweekly-all.service.bak_wave3 \
   /etc/systemd/system/gh-train-biweekly-all.service
systemctl daemon-reload
```

### Rollback quarterly unit (Step 9):
```bash
cp /opt/greenbrain-platform/infra/systemd/gh-train-quarterly.service.bak_wave3 \
   /etc/systemd/system/gh-train-quarterly.service
systemctl daemon-reload
```

### Rollback legacy repo freeze (Step 16):
```bash
chmod -R u+w /opt/greenhouse/repo/
```

---

## 6. Output artifacts

| Artifact | Path | Verify |
|----------|------|--------|
| Updated `dev.env` | `infra/env/dev.env` | `GH_REPO_DIR=/opt/greenbrain-platform/apps/ml-worker` |
| Updated `run_train_missing.sh` | `jobs/run_train_missing.sh` | no `greenhouse/repo` |
| Updated `run_predict_all.sh` | `jobs/run_predict_all.sh` | no `greenhouse/repo` |
| Updated `run_daily_parquet_batches.sh` | `jobs/parquet_export/scripts/...` | no `greenhouse/repo` |
| Updated biweekly unit | `/etc/systemd/system/gh-train-biweekly-all.service` | `WorkingDirectory=` monorepo |
| Updated quarterly unit | `/etc/systemd/system/gh-train-quarterly.service` | `WorkingDirectory=` monorepo; relative Python path |
| Monorepo unit copies | `infra/systemd/gh-train-biweekly-all.service` + quarterly | in sync with live |
| Unit backups | `infra/systemd/*.bak_wave3` | 2 files |
| Read-only legacy repo | `/opt/greenhouse/repo/` | `touch test` → Permission denied |

---

## Wave 3 status at runbook creation

| Step | Status | Notes |
|------|--------|-------|
| Wave 2 verified (Step 1) | ⬜ Pending | Check EnvironmentFile gone |
| Python file diff (Step 2) | ⬜ Pending | 4 files differ (storage abstraction — expected) |
| `GH_REPO_DIR` updated (Step 3) | ⬜ Pending | `sed` one-liner |
| `run_train_missing.sh` (Step 4) | ⬜ Pending | `sed` one-liner |
| `run_predict_all.sh` (Step 5) | ⬜ Pending | 2 `sed` commands |
| `run_daily_parquet_batches.sh` (Step 6) | ⬜ Pending | `sed` one-liner |
| Hardcode check (Step 7) | ⬜ Pending | Gate — 0 legacy paths in 3 scripts |
| biweekly WorkingDirectory (Step 8) | ⬜ Pending | `sed` one-liner + backup |
| quarterly WorkingDirectory + ExecStart (Step 9) | ⬜ Pending | Full unit rewrite |
| daemon-reload (Step 10) | ⬜ Pending | After Steps 8–9 |
| gh-train-missing smoke test (Step 11) | ⬜ Pending | ~2 seconds |
| gh-predict-all PREDICT_LIMIT=1 (Step 12) | ⬜ Pending | ~2 min |
| gh-parquet-export test (Step 13) | ⬜ Pending | ETL gate check first |
| gh-train-biweekly-all env confirm (Step 14) | ⬜ Pending | Start + stop after env log |
| Unit files copied to monorepo (Step 15) | ⬜ Pending | After smoke tests |
| Legacy repo frozen (Step 16) | ⬜ Pending | Last — after all tests pass |
