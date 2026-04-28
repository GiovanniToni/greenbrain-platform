ALTER TABLE gb_customer_companies
  ADD COLUMN IF NOT EXISTS first_downloaded_release_version TEXT,
  ADD COLUMN IF NOT EXISTS first_downloaded_at TIMESTAMPTZ;
