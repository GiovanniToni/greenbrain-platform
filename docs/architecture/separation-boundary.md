# Separation Boundary: greenbrain-platform vs client-runtime
> Authoritative definition of what stays in dev/master and what belongs to the installable runtime.
> Generated: Wave 6 — 2026-03-28.

---

## Principle

`greenbrain-platform` is the development and operational master. It runs against Supabase cloud.
`client-runtime` is the installable customer deliverable. It runs against a local PostgreSQL instance.

**The code is shared. The infrastructure config is not.**

---

## Layer map

```
┌─────────────────────────────────────────────────────────────────┐
│                      greenbrain-platform                        │
│                                                                 │
│  apps/backend/app/          ← SHARED (runtime-portable code)   │
│  apps/frontend/src/         ← SHARED (minus auth layer — ①)    │
│  apps/ml-worker/            ← dev/master only                  │
│                                                                 │
│  apps/backend/.env          ← dev/master only (Supabase URL)   │
│  apps/frontend/.env         ← dev/master only (Supabase keys)  │
│  infra/docker-shadow/       ← dev/master only                  │
│  infra/env/ (secrets)       ← dev/master only                  │
│  sql/                       ← dev/master only                  │
│                                                                 │
│  client-runtime/            ← runtime-specific configs live    │
│      docker/                   here; code is referenced,       │
│      env/                      not copied                      │
│      docs/                                                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Detailed classification

### dev/master only — never ships to customers

| Path | Reason |
|------|--------|
| `apps/backend/.env` | Contains `DATABASE_URL` pointing to Supabase |
| `apps/frontend/.env` | Contains `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` |
| `apps/frontend/src/integrations/supabase/` | Supabase JS SDK init |
| `apps/frontend/src/lib/supabaseClient.ts` | Supabase client wrapper |
| `apps/frontend/src/hooks/useAuth.tsx` | Supabase session/auth hook |
| `apps/ml-worker/` | ML training pipeline, Supabase storage-coupled |
| `infra/docker-shadow/` | Shadow testing against Supabase dev DB |
| `infra/env/` (secrets) | Supabase, DO Spaces, pg_cron credentials |
| `infra/scripts/load_env.sh` | Loads Supabase-specific env vars |
| `sql/` | Supabase schema, pg_cron defs, Supabase-specific RPC functions |
| `_private_secrets_archive/` | Archived credentials |

### runtime-portable — shared between dev/master and client-runtime

| Path | Why portable |
|------|-------------|
| `apps/backend/app/` | Pure SQLAlchemy + FastAPI, zero Supabase SDK usage |
| `apps/backend/requirements.txt` | No Supabase dependencies |
| `apps/backend/app/core/config.py` | Dual-mode: `DATABASE_URL` OR `POSTGRES_*` vars |
| `apps/frontend/src/components/` | UI components, no auth coupling |
| `apps/frontend/src/hooks/useAnalytics*.ts` | All use `apiClient.ts` (fetch-based) |
| `apps/frontend/src/lib/apiClient.ts` | Pure `fetch()`, reads `VITE_API_BASE_URL` |
| `apps/frontend/src/pages/*.tsx` (data pages) | Use `apiClient.ts` hooks only |

### Architecture gaps — runtime-portable in code, but not yet deployable

| Gap | Current state | Required for client-runtime | Target wave |
|-----|--------------|----------------------------|-------------|
| ① Frontend auth | `supabase-js` session | Needs auth replacement or removal | Wave 7 |
| ② SQL schema migrations | Supabase-managed, no migration tooling | Standard migration runner (e.g. Alembic or raw SQL) | Wave 7 |
| ③ Frontend build | No `Dockerfile` in `apps/frontend/` | Dockerfile + `VITE_API_BASE_URL` only build | Wave 7 |
| ④ Backend Dockerfile | No `Dockerfile` in `apps/backend/` | Dockerfile, no Supabase env vars | Wave 7 |
| ⑤ ML worker | Tightly Supabase-coupled | Not scoped for client-runtime | TBD |

---

## DB connection contract

The backend `config.py` already supports both modes without code change:

```
Mode A — dev/master (Supabase):
  DATABASE_URL=postgresql+psycopg://...supabase.com/postgres?sslmode=require

Mode B — client-runtime (local PostgreSQL):
  POSTGRES_HOST=postgres
  POSTGRES_PORT=5432
  POSTGRES_DB=greenbrain
  POSTGRES_USER=greenbrain
  POSTGRES_PASSWORD=<secret>
  POSTGRES_SSLMODE=disable
  (DATABASE_URL must be absent or empty)
```

No backend code change is required to switch modes.

---

## Frontend API vs auth separation

```
SHARED (no change needed):
  src/lib/apiClient.ts         → reads VITE_API_BASE_URL, pure fetch
  src/hooks/useAnalytics*.ts   → all use apiClient.ts
  src/components/analytics/    → no auth coupling

DEV/MASTER ONLY (needs replacement in Wave 7):
  src/integrations/supabase/client.ts   → supabase.createClient(URL, KEY)
  src/lib/supabaseClient.ts             → re-exports supabase client
  src/hooks/useAuth.tsx                 → supabase.auth.getSession()
  src/pages/Login.tsx                   → supabase.auth.signInWithPassword()
```

The data plane (everything under `useAnalytics*`) is already decoupled from Supabase.
Only the auth plane needs a replacement for client-runtime.

---

## What Wave 6 does NOT change

- No `apps/` code is modified
- No `infra/docker-shadow/` is modified
- No live `gb_v2_*` stack is touched
- No Supabase credentials are changed
- No copies or symlinks of app code are created in `client-runtime/`

Wave 6 is additive: it creates structure and templates only.
