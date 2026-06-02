ALTER TABLE public.greenbrain_users
  ADD COLUMN IF NOT EXISTS tenant_code text,
  ADD COLUMN IF NOT EXISTS home_host text DEFAULT 'www.greenbrain.it',
  ADD COLUMN IF NOT EXISTS home_path text DEFAULT '/account',
  ADD COLUMN IF NOT EXISTS user_role text DEFAULT 'customer_admin',
  ADD COLUMN IF NOT EXISTS can_access_app boolean NOT NULL DEFAULT false;

-- Password change tracking and cloud/local sync metadata.
ALTER TABLE public.greenbrain_users
  ADD COLUMN IF NOT EXISTS password_changed_at timestamptz,
  ADD COLUMN IF NOT EXISTS password_changed_by uuid,
  ADD COLUMN IF NOT EXISTS password_change_source text NOT NULL DEFAULT 'initial',
  ADD COLUMN IF NOT EXISTS password_version integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS password_sync_required_at timestamptz,
  ADD COLUMN IF NOT EXISTS password_last_synced_at timestamptz,
  ADD COLUMN IF NOT EXISTS password_last_sync_status text NOT NULL DEFAULT 'not_required',
  ADD COLUMN IF NOT EXISTS password_last_sync_error text,
  ADD COLUMN IF NOT EXISTS password_last_sync_attempt_at timestamptz;

CREATE TABLE IF NOT EXISTS public.greenbrain_user_password_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES public.greenbrain_users(id) ON DELETE SET NULL,
  email text NOT NULL,
  tenant_code text,
  event_type text NOT NULL,
  source text NOT NULL DEFAULT 'local',
  status text NOT NULL DEFAULT 'ok',
  password_version integer,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  details jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS greenbrain_user_password_events_user_idx
  ON public.greenbrain_user_password_events (user_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS greenbrain_user_password_events_email_idx
  ON public.greenbrain_user_password_events (lower(email), occurred_at DESC);

CREATE INDEX IF NOT EXISTS greenbrain_users_password_sync_idx
  ON public.greenbrain_users (tenant_code, password_last_sync_status, password_sync_required_at);
