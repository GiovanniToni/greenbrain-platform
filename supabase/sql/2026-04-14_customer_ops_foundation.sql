BEGIN;

CREATE TABLE IF NOT EXISTS public.gb_customer_companies (
  customer_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_code text UNIQUE,
  company_name text NOT NULL,
  vat_number text,
  contact_name text,
  contact_email text NOT NULL,
  contact_phone text,
  address_line text,
  city text,
  country text,
  onboarding_status text NOT NULL DEFAULT 'lead',
  install_status text NOT NULL DEFAULT 'not_started',
  db_integration_status text NOT NULL DEFAULT 'not_started',
  assigned_release_version text,
  installed_release_version text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.gb_customer_subscriptions (
  customer_id uuid PRIMARY KEY
    REFERENCES public.gb_customer_companies(customer_id) ON DELETE CASCADE,
  stripe_customer_id text,
  stripe_subscription_id text,
  plan_code text,
  subscription_status text NOT NULL DEFAULT 'inactive',
  billing_email text,
  current_period_end timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.gb_customer_delivery (
  customer_id uuid PRIMARY KEY
    REFERENCES public.gb_customer_companies(customer_id) ON DELETE CASCADE,
  assigned_release_version text,
  bundle_generated_at timestamptz,
  bundle_sent_at timestamptz,
  install_status text NOT NULL DEFAULT 'not_started',
  onboarding_status text NOT NULL DEFAULT 'lead',
  go_live_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.gb_customer_db_integrations (
  customer_id uuid PRIMARY KEY
    REFERENCES public.gb_customer_companies(customer_id) ON DELETE CASCADE,
  db_type text,
  db_host text,
  db_port integer,
  db_name text,
  db_schema text,
  connection_status text NOT NULL DEFAULT 'unknown',
  mapping_status text NOT NULL DEFAULT 'not_started',
  initial_etl_status text NOT NULL DEFAULT 'not_started',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.gb_touch_updated_at_customer_ops()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_gb_customer_companies_touch ON public.gb_customer_companies;
CREATE TRIGGER trg_gb_customer_companies_touch
BEFORE UPDATE ON public.gb_customer_companies
FOR EACH ROW
EXECUTE FUNCTION public.gb_touch_updated_at_customer_ops();

DROP TRIGGER IF EXISTS trg_gb_customer_subscriptions_touch ON public.gb_customer_subscriptions;
CREATE TRIGGER trg_gb_customer_subscriptions_touch
BEFORE UPDATE ON public.gb_customer_subscriptions
FOR EACH ROW
EXECUTE FUNCTION public.gb_touch_updated_at_customer_ops();

DROP TRIGGER IF EXISTS trg_gb_customer_delivery_touch ON public.gb_customer_delivery;
CREATE TRIGGER trg_gb_customer_delivery_touch
BEFORE UPDATE ON public.gb_customer_delivery
FOR EACH ROW
EXECUTE FUNCTION public.gb_touch_updated_at_customer_ops();

DROP TRIGGER IF EXISTS trg_gb_customer_db_integrations_touch ON public.gb_customer_db_integrations;
CREATE TRIGGER trg_gb_customer_db_integrations_touch
BEFORE UPDATE ON public.gb_customer_db_integrations
FOR EACH ROW
EXECUTE FUNCTION public.gb_touch_updated_at_customer_ops();

COMMIT;
