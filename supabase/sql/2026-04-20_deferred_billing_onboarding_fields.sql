-- Migration 009: deferred billing + assisted onboarding lifecycle
-- Adds new nullable columns to gb_customer_companies.
-- Safe to run on existing data: all columns are nullable, no defaults required.

ALTER TABLE gb_customer_companies
  ADD COLUMN IF NOT EXISTS subscription_plan          TEXT,
  ADD COLUMN IF NOT EXISTS payment_method_id          TEXT,
  ADD COLUMN IF NOT EXISTS payment_method_last4       TEXT,
  ADD COLUMN IF NOT EXISTS payment_method_brand       TEXT,
  ADD COLUMN IF NOT EXISTS stripe_setup_session_id    TEXT,
  ADD COLUMN IF NOT EXISTS setup_slot_preferred_date  DATE,
  ADD COLUMN IF NOT EXISTS setup_slot_preferred_time  TEXT,
  ADD COLUMN IF NOT EXISTS setup_slot_requested_at    TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS setup_slot_notes           TEXT,
  ADD COLUMN IF NOT EXISTS setup_slot_confirmed_at    TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS setup_slot_scheduled_for   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS data_validated_at          TIMESTAMPTZ;
