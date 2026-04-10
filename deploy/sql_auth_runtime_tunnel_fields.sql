BEGIN;

ALTER TABLE public.greenbrain_runtime_connections
  ADD COLUMN IF NOT EXISTS tunnel_provider text,
  ADD COLUMN IF NOT EXISTS tunnel_public_host text,
  ADD COLUMN IF NOT EXISTS tunnel_local_backend_url text,
  ADD COLUMN IF NOT EXISTS tunnel_status text,
  ADD COLUMN IF NOT EXISTS tunnel_last_seen_at timestamptz,
  ADD COLUMN IF NOT EXISTS tunnel_auth_mode text,
  ADD COLUMN IF NOT EXISTS remote_enabled boolean NOT NULL DEFAULT false;

UPDATE public.greenbrain_runtime_connections
SET
  tunnel_status = COALESCE(tunnel_status, 'not_configured'),
  tunnel_auth_mode = COALESCE(tunnel_auth_mode, 'machine-token')
WHERE true;

COMMIT;
