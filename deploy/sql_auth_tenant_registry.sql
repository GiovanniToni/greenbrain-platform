BEGIN;

CREATE TABLE IF NOT EXISTS public.greenbrain_tenants (
  tenant_code text PRIMARY KEY,
  tenant_name text NOT NULL,
  access_mode text NOT NULL CHECK (access_mode IN ('hosted', 'local-runtime')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  login_host text NOT NULL,
  app_host text NOT NULL,
  backend_base_url text,
  runtime_origin text,
  data_mode text NOT NULL DEFAULT 'hosted-db' CHECK (data_mode IN ('hosted-db', 'local-db-via-tunnel', 'local-db-via-sync')),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.gb_touch_updated_at_generic()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_greenbrain_tenants_touch ON public.greenbrain_tenants;

CREATE TRIGGER trg_greenbrain_tenants_touch
BEFORE UPDATE ON public.greenbrain_tenants
FOR EACH ROW
EXECUTE FUNCTION public.gb_touch_updated_at_generic();

CREATE INDEX IF NOT EXISTS idx_greenbrain_tenants_access_mode
  ON public.greenbrain_tenants (access_mode);

CREATE INDEX IF NOT EXISTS idx_greenbrain_tenants_status
  ON public.greenbrain_tenants (status);

CREATE INDEX IF NOT EXISTS idx_greenbrain_tenants_login_host
  ON public.greenbrain_tenants (login_host);

CREATE INDEX IF NOT EXISTS idx_greenbrain_tenants_app_host
  ON public.greenbrain_tenants (app_host);

INSERT INTO public.greenbrain_tenants
(
  tenant_code,
  tenant_name,
  access_mode,
  status,
  login_host,
  app_host,
  backend_base_url,
  runtime_origin,
  data_mode,
  notes
)
VALUES
(
  'greenbrain',
  'GreenBrain Dev Cloud',
  'hosted',
  'active',
  'www.greenbrain.it',
  'dev.greenbrain.it',
  'https://dev.greenbrain.it/api',
  'cloud',
  'hosted-db',
  'Ambiente dev cloud'
),
(
  'cliente1',
  'Cliente 1 Demo',
  'hosted',
  'active',
  'www.greenbrain.it',
  'cliente1.greenbrain.it',
  'https://cliente1.greenbrain.it/api',
  'cloud',
  'hosted-db',
  'Tenant demo hosted per collaudo'
)
ON CONFLICT (tenant_code) DO UPDATE SET
  tenant_name = EXCLUDED.tenant_name,
  access_mode = EXCLUDED.access_mode,
  status = EXCLUDED.status,
  login_host = EXCLUDED.login_host,
  app_host = EXCLUDED.app_host,
  backend_base_url = EXCLUDED.backend_base_url,
  runtime_origin = EXCLUDED.runtime_origin,
  data_mode = EXCLUDED.data_mode,
  notes = EXCLUDED.notes,
  updated_at = now();

COMMIT;
