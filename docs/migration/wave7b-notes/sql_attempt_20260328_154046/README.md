# client-runtime/sql/

SQL artifacts for the customer-local PostgreSQL instance.

## init/

Scripts mounted into `/docker-entrypoint-initdb.d/` in the postgres container.
Postgres runs these **once**, alphabetically, on first container startup (empty data volume).

| File | Wave | Status | Description |
|------|------|--------|-------------|
| `init/01_bootstrap.sql` | 7A | ✅ ready | Creates `_runtime_bootstrap` marker table and records the wave |

## schema/ (deferred — Wave 7B)

Full schema DDL will live here. Blocked by:
- Schema is currently managed entirely in Supabase (materialized views, custom RPCs, pg_cron)
- A Supabase-to-standard-PostgreSQL translation is required
- Business endpoints will return HTTP 500 until schema is applied

**Do not fake schema completion.** Until Wave 7B, all data endpoints
(`/api/v1/sales`, `/api/v1/analytics`, `/api/v1/dashboard`, etc.) will return
500 on a fresh local DB. This is expected and documented.

## migrations/ (deferred — Wave 7B+)

Alembic or raw SQL incremental migrations for ongoing schema evolution.
Not scoped until the initial schema DDL is complete.
