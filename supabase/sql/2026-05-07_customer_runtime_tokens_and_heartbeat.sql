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

ALTER TABLE public.greenbrain_runtime_connections
  ADD COLUMN IF NOT EXISTS installation_id text,
  ADD COLUMN IF NOT EXISTS public_backend_url text,
  ADD COLUMN IF NOT EXISTS local_backend_url text,
  ADD COLUMN IF NOT EXISTS last_heartbeat_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_heartbeat_payload jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.gb_customer_companies
  ADD COLUMN IF NOT EXISTS runtime_connection_status text,
  ADD COLUMN IF NOT EXISTS latest_installation_id text,
  ADD COLUMN IF NOT EXISTS last_runtime_heartbeat_at timestamptz;

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

CREATE TABLE IF NOT EXISTS public.gb_customer_runtime_provisioning_tokens (
  token_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES public.gb_customer_companies(customer_id) ON DELETE CASCADE,
  tenant_code text NOT NULL,
  token_hash text NOT NULL,
  token_hint text,
  purpose text NOT NULL DEFAULT 'runtime_bind'
    CHECK (purpose IN ('runtime_bind')),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'used', 'revoked', 'expired')),
  expires_at timestamptz,
  used_at timestamptz,
  used_by_installation_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_gb_customer_runtime_tokens_customer
  ON public.gb_customer_runtime_provisioning_tokens(customer_id);

CREATE INDEX IF NOT EXISTS idx_gb_customer_runtime_tokens_tenant
  ON public.gb_customer_runtime_provisioning_tokens(tenant_code);

CREATE INDEX IF NOT EXISTS idx_gb_customer_runtime_tokens_status
  ON public.gb_customer_runtime_provisioning_tokens(status);

CREATE UNIQUE INDEX IF NOT EXISTS uq_gb_customer_runtime_tokens_active_customer
  ON public.gb_customer_runtime_provisioning_tokens(customer_id)
  WHERE status = 'active';

DROP TRIGGER IF EXISTS trg_gb_customer_runtime_tokens_touch
ON public.gb_customer_runtime_provisioning_tokens;

CREATE TRIGGER trg_gb_customer_runtime_tokens_touch
BEFORE UPDATE ON public.gb_customer_runtime_provisioning_tokens
FOR EACH ROW
EXECUTE FUNCTION public.gb_touch_updated_at_generic();

COMMIT;
