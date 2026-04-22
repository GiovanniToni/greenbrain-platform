-- Migration: add cancellation tracking fields to gb_customer_companies
-- Safe to run on existing data: all new columns are nullable with safe defaults.
-- Required by: POST /api/v1/customer-ops/customers/:id/request-cancellation

ALTER TABLE gb_customer_companies
  ADD COLUMN IF NOT EXISTS cancellation_requested      BOOLEAN     NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS cancellation_requested_at   TIMESTAMPTZ;
