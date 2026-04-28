-- Wave 14: GreenBrain per-install auth users table
-- Per-install auth: no shared sessions, no Supabase dependency.
-- Each installation has its own greenbrain_users table.

CREATE TABLE IF NOT EXISTS public.greenbrain_users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           TEXT UNIQUE NOT NULL,
    hashed_password TEXT NOT NULL,
    full_name       TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    is_admin        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS greenbrain_users_email_idx
    ON public.greenbrain_users (email);
