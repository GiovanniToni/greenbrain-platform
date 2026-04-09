# SQL Directory

## schema/
Point-in-time schema snapshots. The live source of truth is the live DB.

- `supabase-schema.sql` — exported from Supabase cloud
- `current-schema.sql` — exported from local Docker PostgreSQL (`gb_v2_postgres`)

Refresh Supabase snapshot:
    source infra/scripts/load_env.sh
    docker exec \
      -e PGPASSWORD="$PG_PASSWORD" \
      gb_v2_postgres \
      pg_dump \
        -h "$PG_HOST" \
        -p "$PG_PORT" \
        -U "$PG_USER" \
        -d "$PG_DB" \
        --schema-only \
        --no-owner \
        --no-acl \
      > sql/schema/supabase-schema.sql

## migrations/
Historical migration files copied from `apps/ml-worker/jobs/migrations/`.
They are reference artifacts and should not be re-applied blindly.

## cron/
Canonical pg_cron definitions exported from the live Supabase `cron.job` table.

## diagnostics/
Reserved for ad-hoc SQL diagnostics.
