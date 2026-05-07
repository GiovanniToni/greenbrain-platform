BEGIN;

CREATE OR REPLACE FUNCTION public.gb_touch_updated_at_generic()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TABLE IF NOT EXISTS public.greenbrain_tenants (
  tenant_code text PRIMARY KEY,
  tenant_name text NOT NULL,
  access_mode text NOT NULL DEFAULT 'hosted'
    CHECK (access_mode IN ('hosted', 'local-runtime')),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'inactive')),
  login_host text NOT NULL DEFAULT 'www.greenbrain.it',
  app_host text NOT NULL,
  backend_base_url text,
  runtime_origin text,
  data_mode text NOT NULL DEFAULT 'hosted-db'
    CHECK (data_mode IN ('hosted-db', 'local-db-via-tunnel', 'local-db-via-sync')),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_greenbrain_tenants_touch
ON public.greenbrain_tenants;

CREATE TRIGGER trg_greenbrain_tenants_touch
BEFORE UPDATE ON public.greenbrain_tenants
FOR EACH ROW
EXECUTE FUNCTION public.gb_touch_updated_at_generic();

CREATE INDEX IF NOT EXISTS idx_greenbrain_tenants_access_mode
  ON public.greenbrain_tenants(access_mode);

CREATE INDEX IF NOT EXISTS idx_greenbrain_tenants_status
  ON public.greenbrain_tenants(status);

CREATE TABLE IF NOT EXISTS public.greenbrain_runtime_connections (
  tenant_code text PRIMARY KEY
    REFERENCES public.greenbrain_tenants(tenant_code) ON DELETE CASCADE,
  connection_mode text NOT NULL DEFAULT 'hosted'
    CHECK (connection_mode IN ('hosted', 'cloud-sync', 'reverse-tunnel')),
  sync_enabled boolean NOT NULL DEFAULT false,
  sync_frequency_minutes integer,
  last_sync_at timestamptz,
  last_sync_status text,
  local_agent_version text,
  runtime_health text,
  installation_id text,
  public_backend_url text,
  local_backend_url text,
  last_heartbeat_at timestamptz,
  last_heartbeat_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.greenbrain_runtime_connections
  ADD COLUMN IF NOT EXISTS installation_id text,
  ADD COLUMN IF NOT EXISTS public_backend_url text,
  ADD COLUMN IF NOT EXISTS local_backend_url text,
  ADD COLUMN IF NOT EXISTS last_heartbeat_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_heartbeat_payload jsonb NOT NULL DEFAULT '{}'::jsonb;

DROP TRIGGER IF EXISTS trg_greenbrain_runtime_connections_touch
ON public.greenbrain_runtime_connections;

CREATE TRIGGER trg_greenbrain_runtime_connections_touch
BEFORE UPDATE ON public.greenbrain_runtime_connections
FOR EACH ROW
EXECUTE FUNCTION public.gb_touch_updated_at_generic();

CREATE TABLE IF NOT EXISTS public.gb_customer_runtime_installations (
  installation_id text PRIMARY KEY,
  customer_id uuid REFERENCES public.gb_customer_companies(customer_id) ON DELETE SET NULL,
  tenant_code text NOT NULL,
  installation_label text,
  runtime_mode text NOT NULL DEFAULT 'customer-local'
    CHECK (runtime_mode IN ('customer-local')),
  connection_mode text NOT NULL DEFAULT 'reverse-tunnel'
    CHECK (connection_mode IN ('reverse-tunnel', 'cloud-sync', 'offline')),
  data_mode text NOT NULL DEFAULT 'local-db-via-tunnel'
    CHECK (data_mode IN ('local-db-via-tunnel', 'local-db-via-sync', 'local-only')),
  installed_release_version text,
  local_agent_version text,
  local_backend_url text,
  public_backend_url text,
  tunnel_public_host text,
  provisioning_status text NOT NULL DEFAULT 'pending'
    CHECK (provisioning_status IN ('pending', 'registered', 'active', 'disabled', 'revoked')),
  runtime_health text,
  last_heartbeat_at timestamptz,
  last_heartbeat_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_sync_at timestamptz,
  last_sync_status text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_gb_customer_runtime_installations_customer
  ON public.gb_customer_runtime_installations(customer_id);

CREATE INDEX IF NOT EXISTS idx_gb_customer_runtime_installations_tenant
  ON public.gb_customer_runtime_installations(tenant_code);

CREATE INDEX IF NOT EXISTS idx_gb_customer_runtime_installations_status
  ON public.gb_customer_runtime_installations(provisioning_status);

DROP TRIGGER IF EXISTS trg_gb_customer_runtime_installations_touch
ON public.gb_customer_runtime_installations;

CREATE TRIGGER trg_gb_customer_runtime_installations_touch
BEFORE UPDATE ON public.gb_customer_runtime_installations
FOR EACH ROW
EXECUTE FUNCTION public.gb_touch_updated_at_generic();

ALTER TABLE public.gb_customer_companies
  ADD COLUMN IF NOT EXISTS runtime_connection_status text,
  ADD COLUMN IF NOT EXISTS latest_installation_id text,
  ADD COLUMN IF NOT EXISTS last_runtime_heartbeat_at timestamptz;

COMMIT;
