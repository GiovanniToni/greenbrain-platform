BEGIN;

ALTER TABLE public.greenbrain_users
  ADD COLUMN IF NOT EXISTS tenant_code text,
  ADD COLUMN IF NOT EXISTS home_host text,
  ADD COLUMN IF NOT EXISTS home_path text,
  ADD COLUMN IF NOT EXISTS user_role text;

COMMIT;
