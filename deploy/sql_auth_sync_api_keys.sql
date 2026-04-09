BEGIN;

CREATE TABLE IF NOT EXISTS public.greenbrain_sync_api_keys (
  tenant_code text PRIMARY KEY
    REFERENCES public.greenbrain_tenants(tenant_code) ON DELETE CASCADE,
  api_key text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_greenbrain_sync_api_keys_touch
ON public.greenbrain_sync_api_keys;

CREATE TRIGGER trg_greenbrain_sync_api_keys_touch
BEFORE UPDATE ON public.greenbrain_sync_api_keys
FOR EACH ROW
EXECUTE FUNCTION public.gb_touch_updated_at_generic();

CREATE INDEX IF NOT EXISTS idx_greenbrain_sync_api_keys_active
  ON public.greenbrain_sync_api_keys (is_active);

INSERT INTO public.greenbrain_sync_api_keys (tenant_code, api_key, is_active)
VALUES
  ('greenbrain', 'CHANGE_ME_GREENBRAIN_SYNC_KEY', true),
  ('cliente1', 'CHANGE_ME_CLIENTE1_SYNC_KEY', true)
ON CONFLICT (tenant_code) DO NOTHING;

COMMIT;
