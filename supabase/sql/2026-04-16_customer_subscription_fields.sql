BEGIN;

CREATE TABLE IF NOT EXISTS public.gb_customer_subscriptions (
    subscription_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id uuid NOT NULL REFERENCES public.gb_customer_companies(customer_id) ON DELETE CASCADE,
    provider text NOT NULL DEFAULT 'stripe',
    plan_code text,
    billing_email text,
    subscription_status text NOT NULL DEFAULT 'pending',
    stripe_customer_id text,
    stripe_subscription_id text,
    stripe_checkout_session_id text,
    current_period_start timestamptz,
    current_period_end timestamptz,
    cancel_at_period_end boolean NOT NULL DEFAULT false,
    activated_at timestamptz,
    canceled_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_gb_customer_subscriptions_customer_id
    ON public.gb_customer_subscriptions(customer_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_gb_customer_subscriptions_stripe_subscription_id
    ON public.gb_customer_subscriptions(stripe_subscription_id)
    WHERE stripe_subscription_id IS NOT NULL;

ALTER TABLE public.gb_customer_companies
ADD COLUMN IF NOT EXISTS subscription_status text,
ADD COLUMN IF NOT EXISTS stripe_customer_id text,
ADD COLUMN IF NOT EXISTS stripe_subscription_id text,
ADD COLUMN IF NOT EXISTS billing_email text;

COMMIT;
