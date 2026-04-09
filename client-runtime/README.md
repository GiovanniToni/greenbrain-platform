# GreenBrain Client Runtime
> Wave 6 complete. Structural skeleton in place. Wave 7 will wire app code and resolve auth.

## Purpose

Separate the installable customer runtime from the development master (`greenbrain-platform`).

- `greenbrain-platform` → dev/master, runs against Supabase
- `client-runtime` → customer-installable, runs against local PostgreSQL

## Rules

- `greenbrain-platform` continues to use Supabase as its database
- `client-runtime` uses customer-local PostgreSQL
- live `gb_v2_*` stack is never touched by migration work
- no app code is copied here — `apps/` is the single source; configs differ

## Directory contents

| Path | Status | Description |
|------|--------|-------------|
| `docker/docker-compose.yml` | ✅ Wave 6 | Local stack template (postgres + backend + frontend) |
| `env/backend.env.template` | ✅ Wave 6 | Backend env template with POSTGRES_* vars |
| `env/frontend.env.template` | ✅ Wave 6 | Frontend env template (VITE_API_BASE_URL only) |
| `docs/install-guide.md` | ✅ Wave 6 | Customer installation guide skeleton |
| `backend/` | ⏳ Wave 7 | Will contain Dockerfile or symlink to apps/backend |
| `frontend/` | ⏳ Wave 7 | Will contain Dockerfile or symlink to apps/frontend |
| `base/` | ⏳ reserved | Shared base layer config |
| `packaging/` | ⏳ reserved | Build artifacts and installers |
| `templates/` | ⏳ reserved | Ansible / CI templates |

## Key references

- `docs/architecture/separation-boundary.md` — authoritative file classification
- `docs/migration/wave-6-runbook.md` — Wave 6 steps, rollback, validation checklist
- `docs/migration/wave-7-runbook.md` — next: Dockerfiles, auth migration, schema runner

## Wave 6 blockers resolved

- Backend code is already 100% runtime-portable (`config.py` supports POSTGRES_* without Supabase)
- Frontend data plane (`useAnalytics*` hooks via `apiClient.ts`) is already runtime-portable
- `docker/docker-compose.yml` and env templates confirm local-postgres architecture

## Wave 7 open items

- ① Frontend auth: Supabase → needs replacement or removal for customer installs
- ② Dockerfiles: `apps/backend/` and `apps/frontend/` need production Dockerfiles
- ③ Schema migration: fresh postgres needs a schema runner (Alembic or raw SQL)

## Validation note
`docker-compose config` requires concrete env files, not only templates.
For structural validation in Wave 6, create:
- `client-runtime/env/backend.env`
- `client-runtime/env/frontend.env`
from the provided templates.
