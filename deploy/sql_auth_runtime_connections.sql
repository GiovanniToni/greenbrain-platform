BEGIN;

CREATE TABLE IF NOT EXISTS public.greenbrain_runtime_connections (
  tenant_code text PRIMARY KEY
    REFERENCES public.greenbrain_tenants(tenant_code) ON DELETE CASCADE,
  connection_mode text NOT NULL
    CHECK (connection_mode IN ('hosted', 'cloud-sync', 'reverse-tunnel')),
  sync_enabled boolean NOT NULL DEFAULT false,
  sync_frequency_minutes integer,
  last_sync_at timestamptz,
  last_sync_status text,
  local_agent_version text,
  runtime_health text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_greenbrain_runtime_connections_touch
ON public.greenbrain_runtime_connections;

CREATE TRIGGER trg_greenbrain_runtime_connections_touch
BEFORE UPDATE ON public.greenbrain_runtime_connections
FOR EACH ROW
EXECUTE FUNCTION public.gb_touch_updated_at_generic();

INSERT INTO public.greenbrain_runtime_connections
(
  tenant_code,
  connection_mode,
  sync_enabled,
  sync_frequency_minutes,
  last_sync_status,
  local_agent_version,
  runtime_health,
  notes
)
VALUES
(
  'greenbrain',
  'hosted',
  false,
  null,
  'n/a',
  'cloud',
  'healthy',
  'Ambiente dev cloud hosted'
),
(
  'cliente1',
  'hosted',
  false,
  null,
  'n/a',
  'cloud',
  'healthy',
  'Tenant demo hosted'
)
ON CONFLICT (tenant_code) DO UPDATE SET
  connection_mode = EXCLUDED.connection_mode,
  sync_enabled = EXCLUDED.sync_enabled,
  sync_frequency_minutes = EXCLUDED.sync_frequency_minutes,
  last_sync_status = EXCLUDED.last_sync_status,
  local_agent_version = EXCLUDED.local_agent_version,
  runtime_health = EXCLUDED.runtime_health,
  notes = EXCLUDED.notes,
  updated_at = now();

COMMIT;
