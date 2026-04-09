# Wave 0 Runbook
> Operator execution checklist. Terminal-oriented. No theory.
> Generated: 2026-03-27. Based on live baseline captured at 17:06 CET.

---

## 1. Objective

Remove two active production hazards without touching any code:
1. Disable pg_cron jobs firing every minute (ETL overcall)
2. Delete exposed Supabase JWT from source tree and rotate the key

Leave the system in exactly the same operational state, with confirmed health documented.

---

## 2. Preconditions

Run all of these before starting. Stop if any check fails.

```bash
# 1. All 6 systemd timers must be active:
systemctl list-timers --all | grep gh-
# Expected: 6 lines, all showing a future "NEXT" date

# 2. All 6 Docker containers must be running:
docker ps --format "{{.Names}}: {{.Status}}" | grep gb_v2
# Expected: 6 lines, all "Up"

# 3. Supabase DB must be reachable:
source /opt/greenbrain-platform/infra/scripts/load_env.sh
psql "$DATABASE_URL" -c "SELECT 1;" -q
# Expected: "1 row" — no error

# 4. Credential file must still exist (confirm before deleting):
find /opt/greenhouse /opt/greenbrain-platform -name "lovabel*" -o -name "lovabel .env corretto.json" 2>/dev/null
# Expected: 1–2 paths printed

# 5. Have Supabase dashboard access open before starting:
#    Project Settings → API → anon/public key → rotate
```

---

## 3. Step-by-step

---

### Step 1 — Verify pg_cron state

**Purpose:** Confirm jobs 30/38/39 are already absent (baseline shows they were removed before this runbook was created) and no `* * * * *` jobs remain.

```bash
source /opt/greenbrain-platform/infra/scripts/load_env.sh
psql "$DATABASE_URL" -P pager=off \
  -c "SELECT jobid, schedule, command FROM cron.job ORDER BY jobid;"
```

**Expected result:** 10 rows. Jobids: 11, 12, 13, 28, 29, 31, 32, 34, 35, 37. No row with schedule `* * * * *`.

```bash
# Confirm zero every-minute jobs:
psql "$DATABASE_URL" -c \
  "SELECT COUNT(*) FROM cron.job WHERE schedule = '* * * * *';"
# Expected: 0
```

**If result differs (jobs 30/38/39 present or `* * * * *` count > 0):**
```bash
# Disable the dangerous jobs:
psql "$DATABASE_URL" -c "SELECT cron.unschedule(30);" 2>/dev/null
psql "$DATABASE_URL" -c "SELECT cron.unschedule(38);" 2>/dev/null
psql "$DATABASE_URL" -c "SELECT cron.unschedule(39);" 2>/dev/null
# Re-run verification above. Expected count must reach 0 before proceeding.
```

**If ETL jobs 11, 29, 37 are absent:** STOP — ETL has no trigger. Do not proceed until these are confirmed present.

✅ **Status at baseline capture (2026-03-27 17:06):** Already complete. 10 rows present, 0 `* * * * *` rows.

---

### Step 2 — Locate credential leak file

**Purpose:** Find the file containing the live `VITE_SUPABASE_PUBLISHABLE_KEY` before deleting it.

```bash
find /opt/greenhouse /opt/greenbrain-platform \
  \( -name "lovabel*" -o -name "*.env corretto*" \) 2>/dev/null
```

**Expected result:** One or two paths, e.g.:
```
/opt/greenhouse/repo/ISTRUZIONI & FUNZIONAMENTO/lovabel .env corretto.json
/opt/greenbrain-platform/apps/ml-worker/ISTRUZIONI & FUNZIONAMENTO/lovabel .env corretto.json
```

**If no paths found:** The file was already deleted. Skip to Step 4 (key rotation still required — the key was exposed in git history and IDE action logs).

**If result differs (unexpected paths):** Note all paths. Delete every instance found.

---

### Step 3 — Delete credential leak file

**Purpose:** Remove the file containing the live JWT from both repos.

```bash
# Delete from legacy repo:
rm "/opt/greenhouse/repo/ISTRUZIONI & FUNZIONAMENTO/lovabel .env corretto.json"

# Delete from monorepo (if present):
rm "/opt/greenbrain-platform/apps/ml-worker/ISTRUZIONI & FUNZIONAMENTO/lovabel .env corretto.json"
```

**Expected result:** `rm` exits silently (exit code 0). No error.

**If file not found:** `rm` will print "No such file or directory" — that is acceptable (already deleted). Not an error.

**If permission denied:** Run with `sudo`. Do not skip.

---

### Step 4 — Verify deletion

**Purpose:** Confirm the file no longer exists in either repo.

```bash
find /opt/greenhouse /opt/greenbrain-platform \
  \( -name "lovabel*" -o -name "*.env corretto*" \) 2>/dev/null
```

**Expected result:** No output (empty).

**If paths still appear:** Re-run Step 3 for each remaining path.

---

### Step 5 — Rotate Supabase publishable key

**Purpose:** Invalidate the exposed JWT. The key was visible in `/opt/greenbrain/frontend/.env` and in IDE session logs. Rotation is mandatory even if the file is deleted.

**Action — in Supabase dashboard (browser):**

1. Go to: `https://supabase.com/dashboard/project/xbyhmzrlycixxrfjggvn/settings/api`
2. Find: **Project API Keys → anon/public**
3. Click **Reveal** → copy the current value to verify it matches what was in the `.env`
4. Click **Generate new key** (or equivalent button for your Supabase version)
5. Copy the new key value — you will need it in Step 6

**Expected result:** New `anon` key generated. Old key is immediately invalidated.

**Side effect:** All active browser sessions using Supabase auth will be logged out. Coordinate timing with users if applicable.

**If you cannot rotate (no dashboard access):** Stop. Do not proceed to Step 6 with the old key. Escalate.

---

### Step 6 — Update frontend `.env` with new key

**Purpose:** Replace the invalidated key in the frontend env file so the container can authenticate.

```bash
# Read current value to confirm it is the old key:
grep VITE_SUPABASE_PUBLISHABLE_KEY /opt/greenbrain/frontend/.env
```

Edit the file and replace the value:
```bash
# Using sed — replace old value with new key:
NEW_KEY="<paste-new-key-here>"
sed -i "s|VITE_SUPABASE_PUBLISHABLE_KEY=.*|VITE_SUPABASE_PUBLISHABLE_KEY=\"${NEW_KEY}\"|" \
  /opt/greenbrain/frontend/.env

# Verify the change:
grep VITE_SUPABASE_PUBLISHABLE_KEY /opt/greenbrain/frontend/.env
# Expected: the new key value
```

**Expected result:** File updated. New key printed. Old key no longer appears.

**If result differs:** Inspect the file manually: `cat /opt/greenbrain/frontend/.env`. Correct the value before continuing.

---

### Step 7 — Restart frontend container

**Purpose:** Force the container to reload the `.env` with the new key.

```bash
docker restart gb_v2_frontend
```

**Expected result:**
```
gb_v2_frontend
```
(Docker prints the container name on success.)

Wait 10 seconds for the Vite dev server to start:
```bash
sleep 10
docker ps --filter name=gb_v2_frontend --format "{{.Names}}: {{.Status}}"
# Expected: gb_v2_frontend: Up N seconds
```

**If container fails to start:**
```bash
docker logs gb_v2_frontend --tail 30
# Look for: "Cannot find module", "VITE_", or npm errors
```

---

### Step 8 — Verify frontend container and HTTP 200

**Purpose:** Confirm the application serves correctly after the key rotation.

```bash
# HTTP check via nginx (primary endpoint):
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8082
# Expected: HTTP 200

# Direct container port:
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8083
# Expected: HTTP 200

# Container health summary:
docker ps --format "{{.Names}}: {{.Status}}" | grep gb_v2
# Expected: 6 containers, all "Up"
```

**If HTTP result is not 200:**
```bash
docker logs gb_v2_nginx --tail 20
docker logs gb_v2_frontend --tail 20
```

**If frontend container is down:** Run `docker start gb_v2_frontend` and wait 15 seconds before re-checking.

**Manual verification required:** Open the frontend URL in a browser. Attempt login with a real account. Confirm that auth succeeds with the new key.

**If login fails after key rotation:** The new key may not have propagated to the Supabase SDK in the running container. Run `docker restart gb_v2_frontend` again and re-test.

---

### Step 9 — Final system health snapshot

**Purpose:** Capture post-Wave-0 state for comparison and record.

```bash
echo "=== TIMERS ===" && systemctl list-timers --all | grep gh-
echo "=== DOCKER ===" && docker ps --format "{{.Names}}: {{.Status}}"
echo "=== CRON JOBS ===" && \
  psql "$DATABASE_URL" -P pager=off \
    -c "SELECT jobid, schedule FROM cron.job ORDER BY jobid;"
```

**Expected result:**
- 6 timers, all active
- 6 Docker containers, all `Up`
- 10 cron jobs, none with `* * * * *`

Append this snapshot to `freeze-baseline.md`:
```bash
cat >> /opt/greenbrain-platform/docs/migration/freeze-baseline.md << 'EOF'

---

## POST-WAVE-0 SNAPSHOT

EOF
echo "Captured: $(date -Is)" >> /opt/greenbrain-platform/docs/migration/freeze-baseline.md
echo "" >> /opt/greenbrain-platform/docs/migration/freeze-baseline.md
echo "### TIMERS" >> /opt/greenbrain-platform/docs/migration/freeze-baseline.md
systemctl list-timers --all | grep gh- >> /opt/greenbrain-platform/docs/migration/freeze-baseline.md
echo "" >> /opt/greenbrain-platform/docs/migration/freeze-baseline.md
echo "### DOCKER" >> /opt/greenbrain-platform/docs/migration/freeze-baseline.md
docker ps --format "{{.Names}}: {{.Status}}" >> /opt/greenbrain-platform/docs/migration/freeze-baseline.md
echo "" >> /opt/greenbrain-platform/docs/migration/freeze-baseline.md
echo "### PG_CRON (post-Wave-0)" >> /opt/greenbrain-platform/docs/migration/freeze-baseline.md
psql "$DATABASE_URL" -P pager=off \
  -c "SELECT jobid, schedule FROM cron.job ORDER BY jobid;" \
  >> /opt/greenbrain-platform/docs/migration/freeze-baseline.md
```

---

## 4. Validation

Run all four checks. All must pass before Wave 0 is declared complete.

### DB validation
```bash
source /opt/greenbrain-platform/infra/scripts/load_env.sh

# No every-minute jobs:
psql "$DATABASE_URL" -c \
  "SELECT COUNT(*) FROM cron.job WHERE schedule = '* * * * *';"
# Must be: 0

# ETL jobs still present:
psql "$DATABASE_URL" -c \
  "SELECT jobid, schedule FROM cron.job WHERE jobid IN (11, 29, 37);"
# Must return 3 rows
```

### systemd validation
```bash
systemctl list-timers --all | grep gh-
# Must show 6 timers, all with a future NEXT date

# No timer should show "failed":
systemctl --failed | grep gh-
# Expected: no output
```

### Docker validation
```bash
docker ps --format "{{.Names}}: {{.Status}}" | grep gb_v2
# Must show 6 containers, all "Up"

# No container should be in restart loop:
docker ps -a --filter status=exited --format "{{.Names}}" | grep gb_v2
# Expected: no output
```

### Frontend validation
```bash
# HTTP 200 from nginx:
curl -s -o /dev/null -w "%{http_code}" http://localhost:8082
# Must be: 200

# Old key no longer in .env:
grep VITE_SUPABASE_PUBLISHABLE_KEY /opt/greenbrain/frontend/.env
# Must NOT match the old key value that was present before Wave 0
```

---

## 5. Rollback

Only the pg_cron step is reversible. Key rotation cannot be undone.

### Rollback pg_cron (only if ETL completely stops)

If jobs 11, 29, 37 are confirmed absent and ETL is not running, re-add them:
```bash
source /opt/greenbrain-platform/infra/scripts/load_env.sh
psql "$DATABASE_URL" -c "
  SELECT cron.schedule(
    'gh-etl-every5-1011',
    '*/5 10-11 * * *',
    \$\$set statement_timeout = 0; call public.run_greenhouse_daily_pipeline_full(40,14,2);\$\$
  );
"
# Verify:
psql "$DATABASE_URL" -c "SELECT jobid, schedule FROM cron.job ORDER BY jobid;"
```

**Do not attempt to rollback jobs 30/38/39.** Those jobs were excessive. Their removal is the correct state.

### Rollback frontend key (not possible)

Once the Supabase anon key is rotated, the old key is permanently invalidated. If the frontend container breaks:
1. Verify the new key in `/opt/greenbrain/frontend/.env` is correct (no extra quotes, no whitespace)
2. `docker restart gb_v2_frontend`
3. Hard-refresh the browser (Ctrl+Shift+R) to clear any cached old key

### No rollback exists for

- Credential file deletion — intentional and correct
- Key rotation — intentional and correct

---

## 6. Output artifacts

The following must exist after Wave 0 is complete:

| Artifact | Path | Check command |
|----------|------|---------------|
| Freeze baseline (pre-Wave-0) | `docs/migration/freeze-baseline.md` | `wc -l docs/migration/freeze-baseline.md` → > 100 lines |
| No credential file | `/opt/greenhouse/repo/ISTRUZIONI*/lovabel*.json` | `find /opt/greenhouse -name "lovabel*"` → no output |
| No credential file | `/opt/greenbrain-platform/apps/ml-worker/ISTRUZIONI*/lovabel*.json` | `find /opt/greenbrain-platform -name "lovabel*"` → no output |
| Rotated key in frontend env | `/opt/greenbrain/frontend/.env` | `grep PUBLISHABLE_KEY` shows new key value |
| Post-Wave-0 snapshot | Appended to `freeze-baseline.md` | `grep "POST-WAVE-0" freeze-baseline.md` → match |

---

## Wave 0 status at runbook creation

Based on the baseline captured at 2026-03-27 17:06 CET:

| Step | Status | Notes |
|------|--------|-------|
| pg_cron 30/38/39 disabled | ✅ Already done | 10 rows in cron.job, 0 with `* * * * *` |
| ETL jobs 11/29/37 active | ✅ Confirmed | All 3 present in baseline |
| freeze-baseline.md written | ✅ Done | 160 lines, all sections populated |
| Credential file deleted | ⬜ **Pending** | Still present — execute Steps 2–4 |
| VITE_SUPABASE_PUBLISHABLE_KEY rotated | ⬜ **Pending** | Execute Steps 5–6 |
| Frontend container restarted with new key | ⬜ **Pending** | Execute Steps 7–8 |
| Post-Wave-0 snapshot appended | ⬜ Pending | Execute Step 9 after all above |

**Remaining work: Steps 2–9 only.**
