BEGIN;

ALTER TABLE public.gb_customer_delivery
ADD COLUMN IF NOT EXISTS bundle_local_path text;

COMMIT;
