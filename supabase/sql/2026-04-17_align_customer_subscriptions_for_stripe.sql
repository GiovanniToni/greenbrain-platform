BEGIN;

ALTER TABLE public.gb_customer_subscriptions
    ADD COLUMN IF NOT EXISTS provider text NOT NULL DEFAULT 'stripe',
    ADD COLUMN IF NOT EXISTS stripe_checkout_session_id text,
    ADD COLUMN IF NOT EXISTS current_period_start timestamptz,
    ADD COLUMN IF NOT EXISTS cancel_at_period_end boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS activated_at timestamptz,
    ADD COLUMN IF NOT EXISTS canceled_at timestamptz;

ALTER TABLE public.gb_customer_subscriptions
    ALTER COLUMN subscription_status SET DEFAULT 'pending';

CREATE UNIQUE INDEX IF NOT EXISTS uq_gb_customer_subscriptions_stripe_checkout_session_id
    ON public.gb_customer_subscriptions(stripe_checkout_session_id)
    WHERE stripe_checkout_session_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_gb_customer_subscriptions_stripe_customer_id
    ON public.gb_customer_subscriptions(stripe_customer_id);

COMMIT;
