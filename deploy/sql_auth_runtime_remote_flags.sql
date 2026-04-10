BEGIN;

ALTER TABLE public.greenbrain_runtime_connections
  ADD COLUMN IF NOT EXISTS remote_route_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS remote_route_mode text,
  ADD COLUMN IF NOT EXISTS remote_route_notes text;

UPDATE public.greenbrain_runtime_connections
SET
  remote_route_mode = COALESCE(remote_route_mode, 'pending'),
  remote_route_notes = COALESCE(remote_route_notes, 'remote route non ancora attiva')
WHERE true;

COMMIT;
