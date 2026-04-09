# Wave 6 Runbook — Structural Separation
> Goal: draw the formal boundary between greenbrain-platform (Supabase) and client-runtime (local PostgreSQL).
> This is a structural wave — no business logic changes, no code moves, no running service changes.
> Generated: 2026-03-28.

---

## 1. Objective

Create the skeleton of `client-runtime/` with the configs, env templates, and documentation that define
what a customer-installable deployment looks like. Document which parts of the existing codebase are
already portable and which are not.

**What this wave is NOT:**
- Not a code rewrite
- Not an auth layer replacement (Wave 7)
- Not a Docker image build (Wave 7)
- Not a data migration
- Not a schema migration tooling change
- Not a change to `apps/` code
- Not a change to `infra/docker-shadow/`
- Not a touch of the live `gb_v2_*` stack

**Authoritative reference:** `docs/architecture/separation-boundary.md`

---

## 2. Preconditions

No code preconditions. Wave 6 is additive and operates only on empty directories.

```bash
# Verify shadow stack still healthy (do not proceed if broken)
docker ps --filter name=docker-shadow --format "{{.Names}}: {{.Status}}"
# Expected: both backend_shadow and frontend_shadow running

# Verify live stack untouched
docker ps --filter name=gb_v2 --format "{{.Names}}: {{.Status}}"
# Expected: gb_v2_frontend, gb_v2_backend, gb_v2_postgres, gb_v2_nginx, gb_v2_ml, gb_v2_pgadmin all Up

# Confirm client-runtime/ skeleton dirs exist
ls /opt/greenbrain-platform/client-runtime/
# Expected: README.md  backend/  base/  docker/  docs/  env/  frontend/  packaging/  templates/
```

---

## 3. Target folder tree after Wave 6

```
client-runtime/
├── README.md                         ← updated: Wave 6 status
├── docker/
│   └── docker-compose.yml            ← NEW: local stack (postgres + backend + frontend)
├── env/
│   ├── backend.env.template          ← NEW: POSTGRES_* vars, no Supabase
│   └── frontend.env.template         ← NEW: VITE_API_BASE_URL only
├── docs/
│   └── install-guide.md              ← NEW: customer installation skeleton
├── backend/                          ← empty; Wave 7 will add Dockerfile or symlink
├── frontend/                         ← empty; Wave 7 will add Dockerfile or symlink
├── base/                             ← empty; reserved
├── packaging/                        ← empty; reserved for Wave 7+ packaging
└── templates/                        ← empty; reserved for Ansible/CI templates

docs/architecture/
└── separation-boundary.md            ← NEW: authoritative boundary definition
```

---

## 4. Step-by-step

All steps are additive. None modify existing files except `client-runtime/README.md`.

---

### Step 1 — Verify separation-boundary.md exists

```bash
cat /opt/greenbrain-platform/docs/architecture/separation-boundary.md | head -5
# Expected: "# Separation Boundary: greenbrain-platform vs client-runtime"
```

---

### Step 2 — Verify client-runtime skeleton files exist

```bash
for f in \
  client-runtime/docker/docker-compose.yml \
  client-runtime/env/backend.env.template \
  client-runtime/env/frontend.env.template \
  client-runtime/docs/install-guide.md; do
  echo -n "$f: "
  test -f /opt/greenbrain-platform/$f && echo "OK" || echo "MISSING"
done
```

**Expected:** all four print `OK`.

---

### Step 3 — Verify env templates do not contain active Supabase vars

```bash
# Ignore comment lines (lines starting with #) — they are documentation only
grep -i 'supabase\|DATABASE_URL' /opt/greenbrain-platform/client-runtime/env/*.template \
  | grep -v '^[^:]*:#' \
  && echo "FAIL: active supabase assignment found" || echo "PASS: no active supabase assignments"
```

**Expected:** `PASS: no active supabase assignments`

---

### Step 4 — Verify docker-compose has no active Supabase URL

```bash
# Ignore comment lines
grep -i 'supabase\|DATABASE_URL' /opt/greenbrain-platform/client-runtime/docker/docker-compose.yml \
  | grep -v '^[[:space:]]*#' \
  && echo "FAIL" || echo "PASS"
```

**Expected:** `PASS`

---

### Step 5 — Verify existing dev/master stack is unaffected

```bash
# Shadow backend still responds
curl -s http://localhost:8001/ | python3 -c "import json,sys; d=json.load(sys.stdin); print('shadow backend:', d.get('status'))"
# Expected: shadow backend: running

# Live backend still responds
curl -s http://localhost:8002/ | python3 -c "import json,sys; d=json.load(sys.stdin); print('live backend:', d.get('status'))" 2>/dev/null || echo "live backend port may differ — check gb_v2_backend"
```

---

### Step 6 — Update client-runtime/README.md

Mark Wave 6 status in the README. (Done as part of Wave 6 artifact creation.)

---

## 5. Rollback

Wave 6 is fully reversible. No existing files are modified (except `client-runtime/README.md` which
was already a placeholder created this session).

```bash
# Full rollback: remove all Wave 6 additions
rm /opt/greenbrain-platform/docs/architecture/separation-boundary.md
rm /opt/greenbrain-platform/client-runtime/docker/docker-compose.yml
rm /opt/greenbrain-platform/client-runtime/env/backend.env.template
rm /opt/greenbrain-platform/client-runtime/env/frontend.env.template
rm /opt/greenbrain-platform/client-runtime/docs/install-guide.md

# Optional: revert README to original placeholder
# git checkout client-runtime/README.md
```

No service restart required. No live stack impact.

---

## 6. Validation checklist

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 1 | Separation boundary doc exists | `test -f docs/architecture/separation-boundary.md && echo OK` | `OK` |
| 2 | docker-compose.yml exists | `test -f client-runtime/docker/docker-compose.yml && echo OK` | `OK` |
| 3 | backend env template exists | `test -f client-runtime/env/backend.env.template && echo OK` | `OK` |
| 4 | frontend env template exists | `test -f client-runtime/env/frontend.env.template && echo OK` | `OK` |
| 5 | No active Supabase assignments in env templates | `grep -i 'supabase\|DATABASE_URL' client-runtime/env/*.template \| grep -v '^[^:]*:#' \|\| echo OK` | `OK` |
| 6 | No active Supabase URL in compose | `grep -i 'supabase\|DATABASE_URL' client-runtime/docker/docker-compose.yml \| grep -v '^[[:space:]]*#' \|\| echo OK` | `OK` |
| 7 | Shadow backend running | `curl -s http://localhost:8001/ \| python3 -c "import json,sys;print(json.load(sys.stdin)['status'])"` | `running` |
| 8 | Live gb_v2 stack unchanged | `docker ps --filter name=gb_v2 \| grep -c Up` | `≥ 3` |
| 9 | client-runtime/backend/ still empty | `ls client-runtime/backend/ \| wc -l` | `0` |
| 10 | No changes to apps/ | `git diff --name-only apps/` | empty |

---

## 7. What Wave 7 picks up from here

Wave 7 (Client-runtime bootstrap — original plan) will:
1. Add `Dockerfile` for backend in `client-runtime/docker/` or `apps/backend/`
2. Add `Dockerfile` for frontend (build with `VITE_API_BASE_URL` only, no Supabase keys)
3. Replace or stub out `src/integrations/supabase/` for the runtime build (auth gap ①)
4. Add a minimal SQL schema migration runner (Alembic or raw SQL script) for local postgres
5. Validate that `client-runtime/docker/docker-compose.yml` brings up a working stack end-to-end
6. Populate `client-runtime/backend/` and `client-runtime/frontend/` (symlinks or Dockerfiles)

---

## 8. Open decisions (not resolved in Wave 6)

| # | Decision | Options | Notes |
|---|----------|---------|-------|
| D1 | Frontend auth for client-runtime | (a) No auth (LAN-only install) / (b) Basic auth via nginx / (c) Separate auth service | Deferred to Wave 7 |
| D2 | App code distribution | (a) Symlinks to `apps/` / (b) Copies / (c) Git submodule / (d) Pre-built Docker images | Deferred to Wave 7 |
| D3 | Schema migration tooling | (a) Alembic / (b) Raw SQL scripts / (c) Liquibase | Deferred to Wave 7 |
| D4 | ML worker for client-runtime | (a) Ship stripped version / (b) Not included / (c) Separate product | TBD — out of scope Wave 6-7 |
