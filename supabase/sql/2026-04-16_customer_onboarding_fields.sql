BEGIN;

ALTER TABLE public.gb_customer_companies
ADD COLUMN IF NOT EXISTS signup_source text,
ADD COLUMN IF NOT EXISTS signup_completed_at timestamptz,
ADD COLUMN IF NOT EXISTS onboarding_step text,
ADD COLUMN IF NOT EXISTS portal_user_email text;

COMMIT;
