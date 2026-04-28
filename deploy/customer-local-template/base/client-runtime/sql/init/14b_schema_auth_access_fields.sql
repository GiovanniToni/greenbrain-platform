ALTER TABLE public.greenbrain_users
  ADD COLUMN IF NOT EXISTS tenant_code text,
  ADD COLUMN IF NOT EXISTS home_host text DEFAULT 'www.greenbrain.it',
  ADD COLUMN IF NOT EXISTS home_path text DEFAULT '/account',
  ADD COLUMN IF NOT EXISTS user_role text DEFAULT 'customer_admin',
  ADD COLUMN IF NOT EXISTS can_access_app boolean NOT NULL DEFAULT false;
