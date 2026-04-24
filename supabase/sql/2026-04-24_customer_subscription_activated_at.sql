ALTER TABLE gb_customer_companies
  ADD COLUMN IF NOT EXISTS subscription_activated_at TIMESTAMPTZ;
