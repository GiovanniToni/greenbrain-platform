# Client-Runtime Technical Design
> Evidence-based. All dependencies verified by grepping the actual codebase.
> No implementation changes yet — design only.

---

## Goal

A self-contained, installable package that runs the full GreenBrain stack on a client's local server
(Linux, single-tenant). No Supabase account, no DigitalOcean account, no internet required at runtime.

---

## Current Cloud Dependency Map

Every external dependency identified from the codebase, with its replacement decision:

| # | Dependency | Files | Used for | Local replacement |
|---|-----------|-------|----------|------------------|
| 1 | **Supabase PostgreSQL** | `backend/app/core/config.py`, all SQL functions | All data storage | Local Postgres 16 + pg_cron |
| 2 | **Supabase Storage (parquet)** | `data_access_v1.py`, `export_features_dense.py` | Parquet files per family+year | Local filesystem via `StorageBackend` abstraction |
| 3 | **Supabase Storage (priors)** | `jobs/upload_priors_to_supabase.py`, `jobs/download_priors_from_supabase.py` | Priors parquet | Same `StorageBackend` abstraction |
| 4 | **Supabase Python SDK** | `data_access_v1.py:create_client`, `export_features_dense.py:create_client` | Storage upload/download | Replaced by `StorageBackend` |
| 5 | **DO Spaces (S3)** | `scripts/spaces_io.py`, `jobs/ensure_model_bundle.py` | Model bundle `.pkl` files | Same `StorageBackend` abstraction |
| 6 | **Supabase Auth** | `src/hooks/useAuth.tsx`, `src/pages/Login.tsx`, `src/components/layout/TopBar.tsx` | User login/session | FastAPI JWT (`/api/v1/auth/`) |
| 7 | **Supabase PostgREST** | `src/hooks/useGardenCenterSettings.ts` | Garden center settings query | FastAPI `GET /api/v1/settings/garden-center` |
| 8 | **`@supabase/supabase-js`** | `src/integrations/supabase/client.ts` | SDK wrapper | Remove entirely after #6 + #7 |

### What is already local-ready (no changes needed)

| Component | Evidence |
|-----------|---------|
| **FastAPI backend** | `config.py` uses `postgres_*` env vars via pydantic-settings — zero Supabase SDK |
| **ETL pipeline** | Runs entirely inside PostgreSQL functions — `run_greenhouse_daily_pipeline_full` is pure SQL |
| **pg_cron jobs** | pg_cron is a Postgres extension, not a Supabase service — works on any local Postgres |
| **Frontend data hooks** | All 20+ hooks use `apiGet`/`apiPost` via `VITE_API_BASE_URL` → FastAPI — zero Supabase data calls |
| **ML Python jobs** | Only need `PG_*` env vars for DB access — no Supabase SDK in the job orchestrators |

---

## Proposed Local Stack

```
                     ┌─────────────────────────────────────────────┐
                     │            CLIENT SERVER (Linux)             │
                     │                                              │
  Browser ──HTTPS──► │  nginx                                       │
                     │    ├── / ──────────────► React SPA (built)   │
                     │    └── /api/ ──────────► FastAPI :8000        │
                     │                              │               │
                     │  PostgreSQL 16 :5432 ◄───────┘               │
                     │    ├── pg_cron (ETL)                         │
                     │    ├── public.* (all tables/functions)       │
                     │    ├── ml_forecast.*                         │
                     │    ├── ml_ops.*                              │
                     │    └── etl.*                                 │
                     │                                              │
                     │  Python venv (ml-worker)                     │
                     │    ├── systemd: gh-predict-all.timer         │
                     │    ├── systemd: gh-train-missing.timer       │
                     │    ├── systemd: gh-parquet-export.timer      │
                     │    └── systemd: gh-refresh-registry.timer    │
                     │                                              │
                     │  Local Storage (filesystem)                  │
                     │    /opt/gh-client/storage/                   │
                     │      ├── models_v4/*.pkl                     │
                     │      ├── features_dense/v1/year=Y/slug=S/    │
                     │      └── priors/priors_v1.parquet            │
                     │                                              │
                     └─────────────────────────────────────────────┘
```

---

## Component Designs

### 1. PostgreSQL (no code change required)

Local Postgres 16 with pg_cron extension. The schema is 100% portable — no Supabase-specific SQL.

```bash
# Setup sequence
apt install postgresql-16 postgresql-16-cron

# Create DB + user
createdb greenbrain
createuser greenbrain

# Apply schema (first install)
psql greenbrain < sql/schema/current-schema.sql

# Apply canonical pg_cron jobs
psql greenbrain < sql/cron/pg_cron_canonical.sql
```

**env vars:**
```bash
PG_HOST=localhost
PG_PORT=5432
PG_DB=greenbrain
PG_USER=greenbrain
PG_PASSWORD=<generated>
PG_SSLMODE=disable
```

**Note on `export_features_dense.py`:** This file currently reads from `SUPABASE_DB_HOST` env vars (not `PG_*`). It needs to be updated to unify on `PG_*` (see §Storage Backend below). It also uses `SUPABASE_DB_PASSWORD` at module level as a required env var — this will crash on local setup without the rename.

---

### 2. Storage Backend Abstraction (NEW — the main engineering work)

The single most impactful change. Replace 4 separate cloud storage integrations with one pluggable backend:

```
apps/ml-worker/storage/
├── __init__.py
├── backend.py          ← StorageBackend protocol + factory
├── local_backend.py    ← LocalStorageBackend
└── s3_backend.py       ← S3StorageBackend (current DO Spaces + any S3)
```

#### Interface (`backend.py`)

```python
class StorageBackend(Protocol):
    def upload(self, remote_key: str, local_path: Path) -> None: ...
    def download(self, remote_key: str, local_path: Path) -> bool: ...
    def exists(self, remote_key: str) -> bool: ...

def get_storage_backend() -> StorageBackend:
    mode = os.getenv("STORAGE_BACKEND", "s3")  # "local" | "s3"
    if mode == "local":
        root = Path(os.environ["LOCAL_STORAGE_ROOT"])
        return LocalStorageBackend(root)
    return S3StorageBackend()   # current boto3 DO Spaces
```

#### `LocalStorageBackend`

```python
class LocalStorageBackend:
    def __init__(self, root: Path):
        self.root = root

    def upload(self, remote_key: str, local_path: Path) -> None:
        dest = self.root / remote_key
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(local_path, dest)

    def download(self, remote_key: str, local_path: Path) -> bool:
        src = self.root / remote_key
        if not src.exists():
            return False
        local_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, local_path)
        return True

    def exists(self, remote_key: str) -> bool:
        return (self.root / remote_key).exists()
```

#### `S3StorageBackend` — wraps the existing `scripts/spaces_io.py` logic, unchanged

The remote key space is identical in both backends. Examples:
- Models: `models_v4/bundle_<slug>_v4.pkl`
- Parquet: `features_dense/v1/year=2025/famiglia_slug=rose/part.parquet`
- Priors: `priors/priors_v1.parquet`

#### Files to update once this abstraction exists

| File | Change |
|------|--------|
| `jobs/ensure_model_bundle.py` | Replace `from scripts.spaces_io import head, download_file, upload_file` → `from storage.backend import get_storage_backend` |
| `jobs/export_features_dense.py` | Replace `create_supabase_client()` + Supabase Storage calls → `get_storage_backend().upload(...)` |
| `jobs/download_priors_from_supabase.py` | Replace `supabase.storage.from_(bucket).download(...)` → `get_storage_backend().download(...)` |
| `jobs/upload_priors_to_supabase.py` | Replace `supabase.storage.from_(bucket).upload(...)` → `get_storage_backend().upload(...)` |
| `data_access_v1.py` | Replace `_supabase_client()` → `get_storage_backend()` (download returns Path, same as current lp) |
| `jobs/export_features_dense.py` | Also rename `SUPABASE_DB_HOST/PORT/NAME/USER/PASSWORD` → `PG_HOST/PORT/DB/USER/PASSWORD` |

**Local env vars for storage:**
```bash
STORAGE_BACKEND=local
LOCAL_STORAGE_ROOT=/opt/gh-client/storage
# DO_SPACES_* env vars not required when STORAGE_BACKEND=local
# SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not required when STORAGE_BACKEND=local
```

**Parquet mode in local runtime:**
- `PARQUET_ENABLE=1` is the recommended local default — parquet avoids repeated full table scans
- With `STORAGE_BACKEND=local`, parquet files are served from `LOCAL_STORAGE_ROOT/features_dense/v1/...`
- `PARQUET_ENABLE=0` also valid — trains/predicts directly from DB, no storage required at all

---

### 3. Auth — Replace Supabase Auth with FastAPI JWT

#### Current scope of Supabase auth in frontend

| File | Usage |
|------|-------|
| `src/pages/Login.tsx` | `supabase.auth.signInWithPassword({ email, password })` |
| `src/components/layout/TopBar.tsx` | `supabase.auth.signOut()` |
| `src/hooks/useAuth.tsx` | `supabase.auth.onAuthStateChange(...)` + `getSession()` |
| `src/hooks/useGardenCenterSettings.ts` | `supabase.from('garden_center_settings').select(...)` |
| `src/lib/supabaseClient.ts` | `fetchProfileData(userId)` — **currently a TODO stub** |

#### Replacement design

**Backend additions:**
```
GET  /api/v1/auth/me                  → { user_id, email, garden_center_id }
POST /api/v1/auth/login               → { access_token, token_type }   (Bearer JWT)
POST /api/v1/auth/logout              → 204
GET  /api/v1/settings/garden-center   → { id, name, timezone, locale }
```

JWT signed with `APP_SECRET` env var. Stateless. No refresh tokens for single-tenant (session lasts `JWT_EXPIRE_HOURS`, default 24h).

Single hardcoded admin user stored in `.env` or a local `users` table (one row). For v1: env vars only — no user management UI needed.

**Frontend additions:**
```
src/lib/localAuthClient.ts   ← replaces integrations/supabase/client.ts
```

```typescript
// src/lib/localAuthClient.ts
export async function signIn(email: string, password: string) {
  const res = await apiPost('/api/v1/auth/login', { email, password });
  sessionStorage.setItem('access_token', res.access_token);
  return res;
}

export function getToken(): string | null {
  return sessionStorage.getItem('access_token');
}

export function signOut() {
  sessionStorage.removeItem('access_token');
}

export function isAuthenticated(): boolean {
  return !!getToken();
}
```

Update `apiGet`/`apiPost` in `apiClient.ts` to attach `Authorization: Bearer <token>` header from `getToken()`.

**Files changed:**
- `src/pages/Login.tsx` — swap `supabase.auth.signInWithPassword` → `signIn` from `localAuthClient`
- `src/components/layout/TopBar.tsx` — swap `supabase.auth.signOut()` → `signOut()`
- `src/hooks/useAuth.tsx` — replace Supabase session listener with polling `GET /api/v1/auth/me`
- `src/hooks/useGardenCenterSettings.ts` — replace `supabase.from(...)` → `apiGet('/api/v1/settings/garden-center')`
- `src/lib/supabaseClient.ts` — re-export from `localAuthClient` for backward compat, then delete
- `src/integrations/supabase/` — whole directory removed
- `package.json` — remove `@supabase/supabase-js`

**Frontend env vars (local):**
```bash
VITE_API_BASE_URL=http://localhost:8000   # or https://greenbrain.client.local
# VITE_SUPABASE_URL           — NOT required
# VITE_SUPABASE_PUBLISHABLE_KEY — NOT required
```

---

### 4. ML Worker (minimal changes after storage abstraction)

Once the `StorageBackend` abstraction is in place, the ML worker is fully local. The remaining
env var differences are:

**Current cloud env vars and their local equivalents:**

| Current (cloud) | Local equivalent | Notes |
|----------------|-----------------|-------|
| `SUPABASE_URL` | *(not needed)* | Storage SDK replaced |
| `SUPABASE_SERVICE_ROLE_KEY` | *(not needed)* | Storage SDK replaced |
| `SUPABASE_BUCKET` | *(not needed)* | `LOCAL_STORAGE_ROOT` replaces |
| `SUPABASE_DB_HOST` | `PG_HOST` | Only in `export_features_dense.py` |
| `SUPABASE_DB_PORT` | `PG_PORT` | Only in `export_features_dense.py` |
| `SUPABASE_DB_NAME` | `PG_DB` | Only in `export_features_dense.py` |
| `SUPABASE_DB_USER` | `PG_USER` | Only in `export_features_dense.py` |
| `SUPABASE_DB_PASSWORD` | `PG_PASSWORD` | Only in `export_features_dense.py` |
| `DO_SPACES_REGION` | *(not needed)* | S3 replaced by local |
| `DO_SPACES_BUCKET` | *(not needed)* | S3 replaced by local |
| `DO_SPACES_KEY` | *(not needed)* | S3 replaced by local |
| `DO_SPACES_SECRET` | *(not needed)* | S3 replaced by local |

**What stays the same in local runtime:**
- All systemd timers — identical schedule, same scripts
- All SQL functions / pg_cron jobs — identical
- All Python job logic — only storage I/O paths change
- `PARQUET_ENABLE`, `PARQUET_FORCE`, `TRAIN_BATCH_SIZE`, `TRAIN_LIMIT`, etc. — unchanged

---

### 5. Frontend / Backend Build

No architectural change. Local deployment simply:
1. `cd apps/frontend && npm run build` → produces `dist/`
2. nginx serves `dist/` at `/` and proxies `/api/` to FastAPI at `localhost:8000`
3. FastAPI runs under systemd as `greenbrain-backend.service`

```nginx
# nginx snippet
location / {
    root /opt/gh-client/frontend/dist;
    try_files $uri $uri/ /index.html;
}

location /api/ {
    proxy_pass http://127.0.0.1:8000/api/;
}
```

---

## Full Env Var Schema for Client Runtime

```bash
# ── POSTGRESQL ────────────────────────────────────────────────
PG_HOST=localhost
PG_PORT=5432
PG_DB=greenbrain
PG_USER=greenbrain
PG_PASSWORD=<generate 32-char random>
PG_SSLMODE=disable

# ── BACKEND ──────────────────────────────────────────────────
APP_SECRET=<generate 64-char random>   # signs JWT tokens
LOCAL_ADMIN_EMAIL=admin@localhost
LOCAL_ADMIN_PASSWORD=<generate>
JWT_EXPIRE_HOURS=24

# ── STORAGE ──────────────────────────────────────────────────
STORAGE_BACKEND=local                  # local | s3
LOCAL_STORAGE_ROOT=/opt/gh-client/storage

# ── ML WORKER ────────────────────────────────────────────────
GH_REPO_DIR=/opt/gh-client/repo
PARQUET_ENABLE=1                       # 1=use local parquet, 0=always DB
PARQUET_FORCE=0
TRAIN_BATCH_SIZE=10
TRAIN_LIMIT=0
V4_SEASONAL_GATE=1

# ── FRONTEND (build-time) ─────────────────────────────────────
VITE_API_BASE_URL=http://localhost:8000
# VITE_SUPABASE_* NOT used in client-runtime
```

---

## Implementation Phases

### Phase 1 — Storage Abstraction (ML side) — unblocks local train/predict

1. Create `apps/ml-worker/storage/__init__.py`, `backend.py`, `local_backend.py`, `s3_backend.py`
2. Update `ensure_model_bundle.py` — replace `scripts.spaces_io` import
3. Update `export_features_dense.py` — replace Supabase storage + unify `SUPABASE_DB_*` → `PG_*`
4. Update `download_priors_from_supabase.py` + `upload_priors_to_supabase.py` — storage-agnostic
5. Update `data_access_v1.py` — replace `_supabase_client()` with storage backend
6. Test: `STORAGE_BACKEND=local PARQUET_ENABLE=1 LOCAL_STORAGE_ROOT=/tmp/test` on a single family

### Phase 2 — Auth Replacement (Frontend + Backend) — unblocks local login

1. Add `POST /api/v1/auth/login`, `GET /api/v1/auth/me`, `POST /api/v1/auth/logout` to FastAPI
2. Add `GET /api/v1/settings/garden-center` to FastAPI
3. Create `apps/frontend/src/lib/localAuthClient.ts`
4. Update `apiClient.ts` to attach Bearer token
5. Rewrite `useAuth.tsx`, `Login.tsx`, `TopBar.tsx`, `useGardenCenterSettings.ts`
6. Delete `src/integrations/supabase/`, `src/lib/supabaseClient.ts`
7. Remove `@supabase/supabase-js` from `package.json`

### Phase 3 — Client Packaging — produces installable artifact

1. Write `client-runtime/base/postgres/init-schema.sh`
2. Write `client-runtime/templates/.env.client.template` (complete, with comments)
3. Write `client-runtime/packaging/install.sh` — full setup on a fresh Debian/Ubuntu server:
   - Install Postgres 16 + pg_cron
   - Create DB + apply schema
   - Create Python venv + install requirements
   - Copy systemd unit files + reload
   - Build frontend
   - Configure nginx
   - Initialize `.env` from template
4. Write `client-runtime/packaging/update.sh` — update existing installation:
   - Pull new code
   - Apply pending migrations
   - Re-build frontend
   - Restart services
5. Test full install on clean VM

---

## What is NOT in Scope for Client-Runtime v1

| Item | Why out of scope |
|------|-----------------|
| Multi-tenant auth / profiles table | Single-tenant: one garden center per server |
| `greenhouse_sales_raw` import connector | Client-specific gestionale; out-of-scope for platform |
| Cloud model bundle registry (`ml_forecast.model_artifact_registry_v1`) | Kept — runs on local PG, no cloud calls |
| Automatic certificate provisioning | Client's IT responsibility |
| Windows support | Linux only (systemd dependency) |
| Docker / container deployment | Phase 4 — after working bare-metal install |

---

## Package Structure (final)

```
client-runtime/
├── base/
│   ├── postgres/
│   │   ├── init-schema.sh          # pg setup: creates DB, applies schema, pg_cron
│   │   └── pg_cron_setup.sql       # canonical 4-job pg_cron config (from sql/cron/)
│   └── nginx/
│       └── nginx.conf.template     # serves SPA + proxies /api/
├── packaging/
│   ├── install.sh                  # full first-time install
│   └── update.sh                   # update existing installation
└── templates/
    └── .env.client.template        # all env vars with inline comments
```

The platform source (`apps/`, `sql/`, `infra/`) remains unchanged — `client-runtime/` is purely
assembly and configuration scripts that consume the platform artifacts.
