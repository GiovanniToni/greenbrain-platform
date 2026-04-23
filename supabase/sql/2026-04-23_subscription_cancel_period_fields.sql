ALTER TABLE gb_customer_companies
  ADD COLUMN IF NOT EXISTS subscription_cancel_at_period_end BOOLEAN,
  ADD COLUMN IF NOT EXISTS subscription_current_period_end TIMESTAMPTZ;
