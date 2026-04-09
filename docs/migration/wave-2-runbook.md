# Wave 2 Runbook
> Env/config consolidation and CLI bin path. Two systemd services migrated.
> Generated: 2026-03-27. Requires careful env diff before any service change.

---

## Objective

Migrate `gh-train-biweekly-all` and `gh-train-quarterly` from `EnvironmentFile=/opt/greenhouse/.env` to the `load_env.sh` system used by the other 4 services. Update `ExecStartPost` to use the monorepo bin path. Remove legacy bin from `$PATH`.

After this wave: `/opt/greenhouse/.env` is referenced by nothing in production.

**WorkingDirectory and Python paths are NOT changed here.** That is Wave 3.

---

## Preconditions

```bash
# Wave 0 must be complete:
source /opt/greenbrain-platform/infra/scripts/load_env.sh
psql "$DATABASE_URL" -c "SELECT COUNT(*) FROM cron.job WHERE schedule = '* * * * *';"
# Expected: 0

# All 6 timers active:
systemctl list-timers --all | grep gh- | wc -l
# Expected: 6

# Confirm biweekly/quarterly timers are not due to fire within the next 2 hours:
systemctl list-timers gh-train-biweekly-all.timer gh-train-quarterly.timer
# Biweekly next: Sun 2026-11-01 (safe — 7 months away)
# Quarterly next: Wed 2026-04-01 (safe — 5 days away)

# Confirm load_env.sh is working:
source /opt/greenbrain-platform/infra/scripts/load_env.sh
echo $DATABASE_URL | cut -c1-20
# Expected: postgresql://... (non-empty, starts with postgresql)

# Confirm monorepo bin has gh-sync-local-artifacts:
ls /opt/greenbrain-platform/infra/scripts/bin/gh-sync-local-artifacts
# Expected: file exists
```

---

## Diff checks

### Full variable diff

```bash
# Extract keys from both files:
grep -E '^[A-Z_]+=' /opt/greenhouse/.env \
  | cut -d= -f1 | sort -u > /tmp/legacy_vars.txt

{
  grep -E '^[A-Z_]+=' /opt/greenbrain-platform/infra/env/base.env
  grep -E '^[A-Z_]+=' /opt/greenbrain-platform/infra/env/dev.env
} | cut -d= -f1 | sort -u > /tmp/new_vars.txt

echo "=== In greenhouse/.env but NOT in base+dev.env ===" && \
  comm -23 /tmp/legacy_vars.txt /tmp/new_vars.txt

echo "=== In base+dev.env but NOT in greenhouse/.env ===" && \
  comm -13 /tmp/legacy_vars.txt /tmp/new_vars.txt
```

**Expected output — missing from dev.env (as of 2026-03-27):**

```
AUTO_TRAIN_MISSING
DO_SPACES_BUCKET
DO_SPACES_KEY
DO_SPACES_REGION
DO_SPACES_SECRET
FAMIGLIE_COL           ← appears 4× in greenhouse/.env — see Step 2
FAMIGLIE_SOURCE_TABLE  ← appears 4× in greenhouse/.env — see Step 2
GH_BASE_DIR
GH_LOG_DIR
GH_REPO_DIR            ← NOTE: keep legacy value /opt/greenhouse/repo for now (Wave 3 changes it)
GH_TMP_DIR
PARQUET_CACHE_DIR
PARQUET_DATASET_PREFIX
PARQUET_ENABLE
PREDICT_LIMIT
SPACES_BETA_PREFIX
SPACES_BT_PREFIX
SPACES_PREFIX
SUPABASE_DB_HOST
SUPABASE_DB_NAME
SUPABASE_DB_PASSWORD
SUPABASE_DB_PORT
SUPABASE_DB_USER
TRAIN_BATCH_SIZE
TRAIN_LIMIT
TRAIN_TIMEOUT_SEC
```

**Note:** `DATABASE_URL` is absent from dev.env intentionally — `load_env.sh` constructs it from `PG_*` vars.

**Note:** `SUPABASE_KEY` is absent from both files. It will be added as an alias in Step 3.

**Present in base+dev.env but not greenhouse/.env (expected):**
```
APP_ENV
GB_REPO
GB_ROOT
LOCAL_STORAGE_ROOT
STORAGE_BACKEND
```
These are monorepo-specific additions. Correct.

---

## Step-by-step commands

---

### Step 1 — Inspect FAMIGLIE_COL and FAMIGLIE_SOURCE_TABLE duplicates

**Purpose:** `greenhouse/.env` defines these 4× each. Understand the values before copying.

```bash
grep "FAMIGLIE_" /opt/greenhouse/.env
```

**Expected:** Multiple lines with different suffix/value variants (e.g. `FAMIGLIE_COL_1`, `FAMIGLIE_COL_2`, or the same key redefined).

**Action:** Note the distinct key names. You will need them for Step 2. If the same key is repeated with different values, the last value wins — confirm which is correct.

---

### Step 2 — Add all missing variables to dev.env

**Purpose:** Transfer all variables present in `greenhouse/.env` but absent from `dev.env`. Without this, the services will fail after the `EnvironmentFile=` line is removed.

**Back up dev.env first:**
```bash
cp /opt/greenbrain-platform/infra/env/dev.env \
   /opt/greenbrain-platform/infra/env/dev.env.bak_wave2
```

**Append the missing block.** Replace `<VALUE>` with actual values from `/opt/greenhouse/.env`:

```bash
# Extract actual values from greenhouse/.env and append to dev.env:
grep -E '^(AUTO_TRAIN_MISSING|DO_SPACES_BUCKET|DO_SPACES_KEY|DO_SPACES_REGION|DO_SPACES_SECRET|GH_BASE_DIR|GH_LOG_DIR|GH_REPO_DIR|GH_TMP_DIR|PARQUET_CACHE_DIR|PARQUET_DATASET_PREFIX|PARQUET_ENABLE|PREDICT_LIMIT|SPACES_BETA_PREFIX|SPACES_BT_PREFIX|SPACES_PREFIX|SUPABASE_DB_HOST|SUPABASE_DB_NAME|SUPABASE_DB_PASSWORD|SUPABASE_DB_PORT|SUPABASE_DB_USER|TRAIN_BATCH_SIZE|TRAIN_LIMIT|TRAIN_TIMEOUT_SEC)=' \
  /opt/greenhouse/.env >> /opt/greenbrain-platform/infra/env/dev.env
```

**Append FAMIGLIE_* separately** (inspect first from Step 1, then append unique keys):
```bash
grep "^FAMIGLIE_" /opt/greenhouse/.env | sort -u \
  >> /opt/greenbrain-platform/infra/env/dev.env
```

**Verify the count of appended variables:**
```bash
wc -l /opt/greenbrain-platform/infra/env/dev.env
# Should be significantly larger than before (was 11 keys — now ~37+)

# Spot-check a critical variable:
grep "^DO_SPACES_KEY=" /opt/greenbrain-platform/infra/env/dev.env
grep "^GH_REPO_DIR=" /opt/greenbrain-platform/infra/env/dev.env
# Expected: one line each, matching values from greenhouse/.env
```

**If any variable is missing:** Append it manually:
```bash
echo 'VARNAME=<value>' >> /opt/greenbrain-platform/infra/env/dev.env
```

---

### Step 3 — Add SUPABASE_KEY and SUPABASE_DB_* aliases

**Purpose:** Add the 6 compatibility aliases required by Wave 4 (storage abstraction). These are derived values, not secrets.

```bash
cat >> /opt/greenbrain-platform/infra/env/dev.env << 'EOF'

# Wave 2: compatibility aliases
# SUPABASE_KEY is a legacy alias used by data_access_v1.py (pre-Wave-4)
SUPABASE_KEY=${SUPABASE_SERVICE_ROLE_KEY}

# SUPABASE_DB_* aliases for export_features_dense.py (uses different naming convention)
# Values are already set in this file from Step 2 — these aliases are no-ops if already present.
# Confirm they exist:
EOF

grep "SUPABASE_DB_\|SUPABASE_KEY" /opt/greenbrain-platform/infra/env/dev.env
```

**Expected:** Lines for `SUPABASE_DB_HOST`, `SUPABASE_DB_PORT`, `SUPABASE_DB_NAME`, `SUPABASE_DB_USER`, `SUPABASE_DB_PASSWORD`, and `SUPABASE_KEY`.

---

### Step 4 — Verify load_env.sh exports all needed variables

**Purpose:** Confirm the new dev.env is complete before touching any unit file.

```bash
# Source it and spot-check critical variables:
source /opt/greenbrain-platform/infra/scripts/load_env.sh

echo "PG_HOST=$PG_HOST"
echo "SUPABASE_URL=$SUPABASE_URL"
echo "DO_SPACES_KEY=${DO_SPACES_KEY:0:8}..."   # show only first 8 chars
echo "GH_REPO_DIR=$GH_REPO_DIR"
echo "GH_LOG_DIR=$GH_LOG_DIR"
echo "DATABASE_URL=${DATABASE_URL:0:30}..."
echo "SUPABASE_KEY=${SUPABASE_KEY:0:8}..."
```

**Expected:** All variables non-empty. `DATABASE_URL` starts with `postgresql://`. `GH_REPO_DIR` is `/opt/greenhouse/repo` (not changed yet — Wave 3).

**If any variable is empty:** Fix `dev.env` before proceeding. Do not edit any unit file until this passes.

---

### Step 5 — Back up current unit files

**Purpose:** Preserve exact originals for rollback.

```bash
cp /etc/systemd/system/gh-train-biweekly-all.service \
   /opt/greenbrain-platform/infra/systemd/gh-train-biweekly-all.service.bak_wave2

cp /etc/systemd/system/gh-train-quarterly.service \
   /opt/greenbrain-platform/infra/systemd/gh-train-quarterly.service.bak_wave2
```

**Note:** Store backups in the monorepo, not in `/etc/systemd/system/` (to avoid the `.bak*` clutter that Wave 1 just cleaned up).

---

### Step 6 — Edit gh-train-biweekly-all.service

**Purpose:** Remove `EnvironmentFile=/opt/greenhouse/.env`. Add `Environment=APP_ENV=dev`. Switch env loading to `load_env.sh`. Update ExecStartPost bin path.

Three changes only:
1. Remove: `EnvironmentFile=/opt/greenhouse/.env`
2. Add: `Environment=APP_ENV=dev`
3. Replace ExecStart's env loading approach
4. Replace ExecStartPost path

Write the new unit file:

```bash
cat > /etc/systemd/system/gh-train-biweekly-all.service << 'UNIT'
[Unit]
Description=Greenhouse - Train ALL Families (biweekly)
After=network-online.target
Wants=network-online.target

[Service]
Environment=APP_ENV=dev
Type=oneshot
User=gh
Group=gh
WorkingDirectory=/opt/greenhouse/repo
ExecStart=/bin/bash -lc 'source /opt/greenbrain-platform/infra/scripts/load_env.sh && source /opt/greenhouse/venv/bin/activate && export RUN_TRIGGER_SOURCE=systemd_timer && python3 -u jobs/train_all_monitor.py'
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
```

**Verify the write:**
```bash
grep "EnvironmentFile" /etc/systemd/system/gh-train-biweekly-all.service
# Expected: no output (line must be gone)

grep "APP_ENV" /etc/systemd/system/gh-train-biweekly-all.service
# Expected: Environment=APP_ENV=dev

grep "gh-sync-local-artifacts" /etc/systemd/system/gh-train-biweekly-all.service
# Expected: /opt/greenbrain-platform/infra/scripts/bin/gh-sync-local-artifacts
```

**Rollback for this step:**
```bash
cp /opt/greenbrain-platform/infra/systemd/gh-train-biweekly-all.service.bak_wave2 \
   /etc/systemd/system/gh-train-biweekly-all.service
systemctl daemon-reload
```

---

### Step 7 — Edit gh-train-quarterly.service

**Purpose:** Same 4 changes as Step 6. The quarterly service additionally exports `GIT_SHA` — preserve that.

```bash
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
WorkingDirectory=/opt/greenhouse/repo
ExecStart=/bin/bash -lc 'source /opt/greenbrain-platform/infra/scripts/load_env.sh && source /opt/greenhouse/venv/bin/activate && export RUN_TRIGGER_SOURCE=systemd_timer && export GIT_SHA="$(cd /opt/greenhouse/repo && git rev-parse --short HEAD 2>/dev/null || true)" && python3 -u /opt/greenhouse/repo/jobs/train_all_monitor.py'
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
```

**Verify:**
```bash
grep "EnvironmentFile" /etc/systemd/system/gh-train-quarterly.service
# Expected: no output

grep "GIT_SHA" /etc/systemd/system/gh-train-quarterly.service
# Expected: the GIT_SHA export line is present (preserved from original)

grep "gh-sync-local-artifacts" /etc/systemd/system/gh-train-quarterly.service
# Expected: monorepo bin path
```

**Rollback for this step:**
```bash
cp /opt/greenbrain-platform/infra/systemd/gh-train-quarterly.service.bak_wave2 \
   /etc/systemd/system/gh-train-quarterly.service
systemctl daemon-reload
```

---

### Step 8 — daemon-reload

**Purpose:** Apply the unit file changes to the running systemd instance.

```bash
systemctl daemon-reload
```

**Expected result:** Silent (no output = success).

```bash
# Confirm units are parsed correctly:
systemctl show gh-train-biweekly-all --property=EnvironmentFiles
# Expected: empty or blank (no EnvironmentFile= set)

systemctl show gh-train-quarterly --property=EnvironmentFiles
# Expected: empty or blank

systemctl show gh-train-biweekly-all --property=Environment
# Expected: APP_ENV=dev

# Confirm timers still active after reload:
systemctl list-timers --all | grep gh- | wc -l
# Expected: 6
```

**If daemon-reload fails:** Check for syntax errors:
```bash
systemd-analyze verify /etc/systemd/system/gh-train-biweekly-all.service
systemd-analyze verify /etc/systemd/system/gh-train-quarterly.service
```
Fix any reported errors before continuing.

---

### Step 9 — Smoke test biweekly service with TRAIN_LIMIT=1

**Purpose:** Confirm the service starts, loads env correctly, and exits cleanly — without running a full training cycle.

```bash
# Start manually with a 1-family limit:
systemctl start gh-train-biweekly-all
```

This will run synchronously (Type=oneshot). Wait for it to complete (~2 min for env check + 1-family train).

```bash
# Check exit status:
systemctl status gh-train-biweekly-all --no-pager -l | head -20

# Check logs:
journalctl -u gh-train-biweekly-all -n 30 --no-pager
```

**Expected in logs:**
```
[ENV] loaded base.env + dev.env
[ENV] DATABASE_URL ready
START ...
```
And exit status 0 (green `inactive (dead)` with `status=0/SUCCESS`).

**If logs show `EnvironmentFile` load error:** The old unit file is cached. Run `systemctl daemon-reload` again.

**If logs show `[ENV][ERROR] invalid PG_HOST`:** `dev.env` is missing `PG_HOST`. Fix and retry.

**If logs show `ModuleNotFoundError` or Python import error:** This is a WorkingDirectory issue — NOT a Wave 2 issue. WorkingDirectory is still `/opt/greenhouse/repo` as intended. If imports fail from this path, stop and investigate before continuing Wave 2.

**Rollback if test fails:**
```bash
cp /opt/greenbrain-platform/infra/systemd/gh-train-biweekly-all.service.bak_wave2 \
   /etc/systemd/system/gh-train-biweekly-all.service
systemctl daemon-reload
```

---

### Step 10 — Smoke test quarterly service with TRAIN_LIMIT=1

```bash
systemctl start gh-train-quarterly
journalctl -u gh-train-quarterly -n 30 --no-pager
```

**Expected:** Same as Step 9. `[ENV] loaded base.env + dev.env`, exit status 0.

**Rollback if test fails:**
```bash
cp /opt/greenbrain-platform/infra/systemd/gh-train-quarterly.service.bak_wave2 \
   /etc/systemd/system/gh-train-quarterly.service
systemctl daemon-reload
```

---

### Step 11 — Copy updated unit files to monorepo

**Purpose:** Keep `infra/systemd/` in sync with `/etc/systemd/system/` after the changes.

```bash
cp /etc/systemd/system/gh-train-biweekly-all.service \
   /opt/greenbrain-platform/infra/systemd/gh-train-biweekly-all.service

cp /etc/systemd/system/gh-train-quarterly.service \
   /opt/greenbrain-platform/infra/systemd/gh-train-quarterly.service
```

**Verify no `EnvironmentFile` line in monorepo copies:**
```bash
grep "EnvironmentFile" /opt/greenbrain-platform/infra/systemd/gh-train-biweekly-all.service
grep "EnvironmentFile" /opt/greenbrain-platform/infra/systemd/gh-train-quarterly.service
# Expected: no output for both
```

---

### Step 12 — Remove legacy bin from PATH

**Purpose:** `/home/gh/.bashrc` adds `/opt/greenhouse/bin` before the monorepo bin, so interactive shell commands resolve to the legacy scripts. Remove this so all `gh-*` commands use the monorepo bin.

**Locate the line:**
```bash
grep -n "greenhouse/bin" /home/gh/.bashrc
# Expected: one line, e.g.:
# 42: export PATH="/opt/greenhouse/bin:$PATH"
```

**Edit the file** to remove or comment out that line:
```bash
# Comment out (safer than delete — easy to revert):
LINE=$(grep -n "greenhouse/bin" /home/gh/.bashrc | cut -d: -f1)
sed -i "${LINE}s|^|# REMOVED wave2: |" /home/gh/.bashrc
```

**Verify the change:**
```bash
grep "greenhouse/bin" /home/gh/.bashrc
# Expected: the line now starts with `# REMOVED wave2:`
```

**Apply to the current shell session:**
```bash
source /home/gh/.bashrc
# OR for root: source ~/.bashrc
```

**Note:** This change only affects interactive shell sessions (`/home/gh/.bashrc`). systemd services do not use `.bashrc`. The ExecStartPost bin path was already updated in Steps 6–7.

---

### Step 13 — Verify PATH resolution

```bash
# Confirm gh-* commands now resolve to monorepo bin:
which gh-sync-local-artifacts
# Expected: /opt/greenbrain-platform/infra/scripts/bin/gh-sync-local-artifacts

which gh-predict-all
# Expected: /opt/greenbrain-platform/infra/scripts/bin/gh-predict-all

which gh-refresh-registry
# Expected: /opt/greenbrain-platform/infra/scripts/bin/gh-refresh-registry

# Confirm legacy bin is NOT first:
echo $PATH | tr ':' '\n' | grep -n "bin"
# greenhouse/bin must appear AFTER greenbrain-platform/infra/scripts/bin, or not at all
```

**If legacy bin still appears first:** The `.bashrc` change did not apply to the current shell. Run `exec bash` or open a new terminal and re-check.

---

## Validation

Run all checks. All must pass before Wave 2 is declared complete.

```bash
source /opt/greenbrain-platform/infra/scripts/load_env.sh

# === Env completeness ===
echo "--- Env check ---"
for v in PG_HOST SUPABASE_URL DO_SPACES_KEY GH_REPO_DIR GH_LOG_DIR \
          SUPABASE_DB_HOST SUPABASE_KEY DATABASE_URL; do
  val="${!v}"
  if [ -z "$val" ]; then
    echo "FAIL: $v is empty"
  else
    echo "OK: $v=${val:0:20}..."
  fi
done

# === Unit files ===
echo "--- Unit file check ---"
grep "EnvironmentFile" /etc/systemd/system/gh-train-biweekly-all.service \
  && echo "FAIL: EnvironmentFile still present" || echo "OK: biweekly"
grep "EnvironmentFile" /etc/systemd/system/gh-train-quarterly.service \
  && echo "FAIL: EnvironmentFile still present" || echo "OK: quarterly"

grep "infra/scripts/bin/gh-sync-local-artifacts" \
  /etc/systemd/system/gh-train-biweekly-all.service \
  && echo "OK: biweekly ExecStartPost" || echo "FAIL: biweekly ExecStartPost not updated"

grep "infra/scripts/bin/gh-sync-local-artifacts" \
  /etc/systemd/system/gh-train-quarterly.service \
  && echo "OK: quarterly ExecStartPost" || echo "FAIL: quarterly ExecStartPost not updated"

# === systemd ===
echo "--- systemd check ---"
systemctl show gh-train-biweekly-all --property=EnvironmentFiles
# Expected: blank

systemctl list-timers --all | grep gh- | wc -l
# Expected: 6

# === PATH ===
echo "--- PATH check ---"
which gh-sync-local-artifacts
# Expected: /opt/greenbrain-platform/infra/scripts/bin/

# === No /opt/greenhouse/.env dependency ===
echo "--- Legacy env check ---"
grep "EnvironmentFile=/opt/greenhouse" /etc/systemd/system/*.service 2>/dev/null
# Expected: no output

# === All containers still up ===
echo "--- Docker check ---"
docker ps --format "{{.Names}}: {{.Status}}" | grep gb_v2 | wc -l
# Expected: 6
```

---

## Rollback

### Rollback env (dev.env):
```bash
cp /opt/greenbrain-platform/infra/env/dev.env.bak_wave2 \
   /opt/greenbrain-platform/infra/env/dev.env
```

### Rollback unit files (both services):
```bash
cp /opt/greenbrain-platform/infra/systemd/gh-train-biweekly-all.service.bak_wave2 \
   /etc/systemd/system/gh-train-biweekly-all.service

cp /opt/greenbrain-platform/infra/systemd/gh-train-quarterly.service.bak_wave2 \
   /etc/systemd/system/gh-train-quarterly.service

systemctl daemon-reload

# Verify EnvironmentFile is restored:
grep "EnvironmentFile" /etc/systemd/system/gh-train-biweekly-all.service
# Expected: EnvironmentFile=/opt/greenhouse/.env
```

### Rollback PATH:
```bash
# Re-enable the commented-out line in .bashrc:
sed -i 's|^# REMOVED wave2: export PATH|export PATH|' /home/gh/.bashrc
source /home/gh/.bashrc
which gh-sync-local-artifacts
# Expected: /opt/greenhouse/bin/gh-sync-local-artifacts
```

---

## Output artifacts

| Artifact | Path | Verify |
|----------|------|--------|
| Updated dev.env | `infra/env/dev.env` | contains `DO_SPACES_KEY`, `GH_REPO_DIR`, `SUPABASE_KEY` |
| dev.env backup | `infra/env/dev.env.bak_wave2` | exists |
| Updated biweekly unit | `/etc/systemd/system/gh-train-biweekly-all.service` | no `EnvironmentFile=` line |
| Updated quarterly unit | `/etc/systemd/system/gh-train-quarterly.service` | no `EnvironmentFile=` line |
| Monorepo unit copies | `infra/systemd/gh-train-biweekly-all.service` + quarterly | in sync with live |
| Unit backups | `infra/systemd/*.bak_wave2` | 2 files |
| Updated .bashrc | `/home/gh/.bashrc` | `greenhouse/bin` commented out |
| PATH resolution | shell | `which gh-*` → monorepo bin |

---

## Wave 2 status at runbook creation

| Step | Status | Notes |
|------|--------|-------|
| Env diff documented | ✅ Done | ~25 vars missing from dev.env |
| dev.env expanded (Step 2) | ⬜ Pending | All missing vars must be added |
| SUPABASE_KEY alias (Step 3) | ⬜ Pending | Add after Step 2 |
| load_env.sh verified (Step 4) | ⬜ Pending | Gate before any service edit |
| biweekly service migrated (Step 6) | ⬜ Pending | After Step 4 passes |
| quarterly service migrated (Step 7) | ⬜ Pending | After Step 6 passes |
| daemon-reload (Step 8) | ⬜ Pending | After Steps 6–7 |
| biweekly smoke test (Step 9) | ⬜ Pending | TRAIN_LIMIT=1 manual start |
| quarterly smoke test (Step 10) | ⬜ Pending | TRAIN_LIMIT=1 manual start |
| Monorepo copies updated (Step 11) | ⬜ Pending | After smoke tests pass |
| PATH updated (Step 12) | ⬜ Pending | Last — after service tests |
| PATH verified (Step 13) | ⬜ Pending | |
