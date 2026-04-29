# GreenBrain environment policy

## Dev cloud

`deploy/env/dev-cloud.env` is the local runtime env for the GreenBrain owner/development cloud stack.

Rules:

- It must use Supabase cloud.
- It must not point to `dev_postgres`.
- It must not point to any local PostgreSQL container.
- The real file may contain secrets and must not be committed.
- Use `deploy/env/dev-cloud.env.example` as the committed template.

Current expected runtime target:

- `POSTGRES_HOST=aws-1-eu-west-1.pooler.supabase.com`
- `POSTGRES_DB=postgres`
- `POSTGRES_SSLMODE=require`

Important: the logical environment is called `dev`, but the actual Supabase PostgreSQL database name is `postgres`.

## Client local runtime

Local PostgreSQL is allowed only for installed customer runtime bundles, for example:

- `greenbrain_local_postgres`
- customer-local bundle installations
- local demo/runtime validation

It must not be used for the GreenBrain owner dev cloud stack.
