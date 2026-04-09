# Wave 7A Runbook — Client-Runtime Backend Bootstrap Formalization
> Goal: replace the ad-hoc pip-install-in-entrypoint pattern with a proper built image,
> add healthchecks, and mount a postgres init script placeholder.
> This is an infrastructure wave — no business logic changes, no schema DDL, no frontend.
> Generated: 2026-03-28.

---

## 1. Objective

Formalize the client-runtime backend boot so that:
- The backend image is built from a proper `Dockerfile` (not `pip install` in the compose command)
- The backend reports `healthy` via Docker's healthcheck mechanism
- Postgres runs a minimal init script on first startup that marks the bootstrap wave
- All infrastructure endpoints (`/health`, `/health/db`, `/api/v1/system/info`) work reliably
- The known schema gap is explicitly documented, not hidden

**What this wave is NOT:**
- Not a schema migration (Wave 7B)
- Not a frontend activation (still behind `wave7-frontend` profile)
- Not an auth replacement
- Not a data population step
- Not a change to `apps/` business logic

**Expected state after Wave 7A:**
```
/health         → {"status": "ok"}
/health/db      → {"status": "ok", "database": "connected"}
/api/v1/system/info  → {"backend_status": "running", ...}
/api/v1/sales/summary → HTTP 500  ← expected; schema not yet loaded (Wave 7B)
_runtime_bootstrap table → 1 row with wave='wave-7a'
```

---

## 2. New artifacts created

| Path | Type | Description |
|------|------|-------------|
| `apps/backend/Dockerfile` | NEW | Proper backend image: copies requirements.txt + app/, runs uvicorn |
| `apps/backend/.dockerignore` | NEW | Excludes .env, __pycache__, .git from build context |
| `client-runtime/sql/README.md` | NEW | Documents sql/ structure and schema gap |
| `client-runtime/sql/init/01_bootstrap.sql` | NEW | Creates `_runtime_bootstrap` marker on first postgres boot |
| `client-runtime/docker/docker-compose.yml` | MODIFIED | backend: build + healthcheck; postgres: init mount |

Baseline snapshot (pre-7A): `client-runtime/docker/docker-compose.yml.wave7a_baseline`

---

## 3. Preconditions

```bash
# Stack must be down before proceeding
cd /opt/greenbrain-platform/client-runtime/docker
docker-compose -f docker-compose.yml ps
# Expected: no running containers (or empty output)

# Wave 6 artifacts must be in place
for f in \
  /opt/greenbrain-platform/apps/backend/Dockerfile \
  /opt/greenbrain-platform/apps/backend/.dockerignore \
  /opt/greenbrain-platform/client-runtime/sql/init/01_bootstrap.sql \
  /opt/greenbrain-platform/client-runtime/env/backend.env; do
  test -f "$f" && echo "OK  $f" || echo "MISSING $f"
done
# Expected: all OK

# Live stack must be untouched
docker ps --filter name=gb_v2 --format "{{.Names}}: {{.Status}}" | grep -c Up
# Expected: >= 3

# Shadow stack must be untouched
docker ps --filter name=docker-shadow --format "{{.Names}}: {{.Status}}"
# Expected: both shadow containers running
```

---

## 4. Step-by-step commands

All commands run from `/opt/greenbrain-platform/client-runtime/docker/` unless stated.

---

### Step 1 — Verify postgres data volume state

```bash
# If postgres_data already exists from the Wave 6 bootstrap,
# the init script will NOT run again (postgres runs initdb only once).
# To get a clean DB with the init script:
docker volume ls | grep postgres
# If docker_postgres_data exists and you want a clean init:
docker volume rm docker_postgres_data
# If you want to keep existing data, skip this step.
```

---

### Step 2 — Build the backend image

```bash
cd /opt/greenbrain-platform/client-runtime/docker

docker-compose -f docker-compose.yml build backend
```

**Expected output (condensed):**
```
Building backend
Step 1/6 : FROM python:3.11-slim
Step 2/6 : WORKDIR /app
Step 3/6 : COPY requirements.txt .
Step 4/6 : RUN pip install --no-cache-dir -r requirements.txt
Step 5/6 : COPY app/ ./app/
Step 6/6 : EXPOSE 8000
Successfully built <image_id>
Successfully tagged docker_backend:latest
```

---

### Step 3 — Start the stack

```bash
docker-compose -f docker-compose.yml up -d
```

**Expected:**
```
Creating network "docker_default" with the default driver
Creating docker_postgres_1 ... done
Creating docker_backend_1  ... done
```

---

### Step 4 — Wait for healthchecks to pass

```bash
# Poll until both services are healthy (up to 60s)
for i in $(seq 1 12); do
  STATUS=$(docker-compose -f docker-compose.yml ps --format json 2>/dev/null \
    | python3 -c "
import json, sys
lines = sys.stdin.read().strip().split('\n')
for line in lines:
    try:
        d = json.loads(line)
        print(d.get('Name','?'), d.get('Health','no-health'))
    except: pass
" 2>/dev/null || docker-compose -f docker-compose.yml ps)
  echo "$STATUS"
  echo "$STATUS" | grep -q "unhealthy" && { echo "UNHEALTHY — waiting..."; sleep 5; continue; }
  echo "$STATUS" | grep -qE "(starting|health: starting)" && { echo "STARTING — waiting..."; sleep 5; continue; }
  break
done
```

**Expected once stable:**
```
docker_postgres_1   healthy
docker_backend_1    healthy
```

---

### Step 5 — Validate infrastructure endpoints

```bash
echo "=== /health ===" && \
curl -s http://127.0.0.1:8000/health | python3 -m json.tool

echo "=== /health/db ===" && \
curl -s http://127.0.0.1:8000/health/db | python3 -m json.tool

echo "=== /api/v1/system/info ===" && \
curl -s http://127.0.0.1:8000/api/v1/system/info | python3 -m json.tool

echo "=== /api/v1/system/db-info ===" && \
curl -s http://127.0.0.1:8000/api/v1/system/db-info | python3 -m json.tool
```

**Expected:**
```json
{"status": "ok"}
{"status": "ok", "database": "connected", "result": {"ok": 1}}
{"backend_status": "running", "api_version": "v1", ...}
{"database_connected": true, "database_name": "greenbrain", ...}
```

---

### Step 6 — Verify bootstrap marker table

```bash
docker exec docker_postgres_1 \
  psql -U greenbrain -d greenbrain \
  -c "SELECT id, wave, applied_at, note FROM _runtime_bootstrap;"
```

**Expected:**
```
 id |   wave   |          applied_at           |                        note
----+----------+-------------------------------+---------------------------------------------
  1 | wave-7a  | 2026-...                      | infrastructure bootstrap: ...
(1 row)
```

> If the volume was kept from Wave 6 (init script did not re-run), this table will not exist.
> That is fine — skip this check and note it in the validation log.

---

### Step 7 — Confirm business endpoints return expected 500

```bash
echo "=== sales/summary (expect 500 — schema not loaded) ===" && \
curl -s "http://127.0.0.1:8000/api/v1/sales/summary?date_from=2025-01-01&date_to=2025-12-31" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('status_code_in_detail:', d.get('detail','')[:60])"
```

**Expected:** 500 with a detail message mentioning the missing table/view.
This is correct behaviour. Document it, do not fix it here.

---

### Step 8 — Confirm live and shadow stacks are unaffected

```bash
# Live stack
docker ps --filter name=gb_v2 --format "{{.Names}}: {{.Status}}"
# Expected: gb_v2_* containers all Up

# Shadow stack
curl -s http://localhost:8001/health | python3 -m json.tool
# Expected: {"status": "ok"}
```

---

## 5. Rollback

Wave 7A is fully reversible.

```bash
# 1. Stop client-runtime stack
cd /opt/greenbrain-platform/client-runtime/docker
docker-compose -f docker-compose.yml down

# 2. Restore compose from baseline snapshot
cp docker-compose.yml.wave7a_baseline docker-compose.yml

# 3. Remove the built image
docker image rm docker_backend 2>/dev/null || true

# 4. Remove Dockerfile and .dockerignore from apps/backend/
rm /opt/greenbrain-platform/apps/backend/Dockerfile
rm /opt/greenbrain-platform/apps/backend/.dockerignore

# 5. Remove sql/ artifacts
rm -rf /opt/greenbrain-platform/client-runtime/sql/

# 6. Optionally remove the postgres data volume (if clean state desired)
docker volume rm docker_postgres_data 2>/dev/null || true
```

No service restart required for live or shadow stacks.

---

## 6. Validation checklist

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 1 | Dockerfile exists | `test -f apps/backend/Dockerfile && echo OK` | `OK` |
| 2 | .dockerignore exists | `test -f apps/backend/.dockerignore && echo OK` | `OK` |
| 3 | init SQL exists | `test -f client-runtime/sql/init/01_bootstrap.sql && echo OK` | `OK` |
| 4 | compose uses build: | `grep 'build:' client-runtime/docker/docker-compose.yml && echo OK` | `OK` |
| 5 | compose mounts init/ | `grep 'docker-entrypoint-initdb.d' client-runtime/docker/docker-compose.yml && echo OK` | `OK` |
| 6 | backend healthcheck defined | `grep 'urllib.request' client-runtime/docker/docker-compose.yml && echo OK` | `OK` |
| 7 | `/health` returns ok | `curl -s http://127.0.0.1:8000/health \| python3 -c "import json,sys;print(json.load(sys.stdin)['status'])"` | `ok` |
| 8 | `/health/db` returns connected | `curl -s http://127.0.0.1:8000/health/db \| python3 -c "import json,sys;print(json.load(sys.stdin)['database'])"` | `connected` |
| 9 | docker ps shows healthy | `docker-compose -f client-runtime/docker/docker-compose.yml ps` | both healthy |
| 10 | shadow backend untouched | `curl -s http://localhost:8001/health \| python3 -c "import json,sys;print(json.load(sys.stdin)['status'])"` | `ok` |
| 11 | live gb_v2 untouched | `docker ps --filter name=gb_v2 \| grep -c Up` | `>= 3` |

---

## 7. What remains deferred (Wave 7B and beyond)

| # | Item | Blocked by | Target |
|---|------|-----------|--------|
| ① | Full schema DDL | Supabase-specific views/RPCs require translation | Wave 7B |
| ② | Business endpoint functionality | Depends on schema DDL | Wave 7B |
| ③ | Frontend standalone | Auth layer still Supabase-coupled | Wave 7B |
| ④ | Data population / migration tooling | Depends on schema DDL | Wave 7B |
| ⑤ | Production image publishing | Requires registry and CI | Wave 7C+ |
| ⑥ | ML worker for client-runtime | Entirely Supabase-coupled, separate product decision | TBD |

---

## 8. Dockerfile reference

`@/opt/greenbrain-platform/apps/backend/Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Design decisions:**
- `COPY requirements.txt` before `COPY app/` — layer cache: dependency layer only
  rebuilds when `requirements.txt` changes, not on every code change
- No `--reload` in CMD — customer runtime does not need hot-reload
- No `HEALTHCHECK` in Dockerfile — managed by docker-compose for flexibility
- `EXPOSE 8000` — documentation only; actual port binding is in compose
