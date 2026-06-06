-- Customer security alerts for operational admin visibility.
-- Initial use case: self-service password reset requests.
-- No raw reset token, password, or token hash is stored here.

CREATE TABLE IF NOT EXISTS public.greenbrain_customer_security_alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid REFERENCES public.gb_customer_companies(customer_id) ON DELETE SET NULL,
  tenant_code text,
  email text NOT NULL,
  alert_type text NOT NULL,
  status text NOT NULL DEFAULT 'open',
  severity text NOT NULL DEFAULT 'info',
  title text NOT NULL,
  message text NOT NULL,
  source text NOT NULL DEFAULT 'system',
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT greenbrain_customer_security_alerts_type_chk
    CHECK (alert_type IN ('password_reset_self_service')),
  CONSTRAINT greenbrain_customer_security_alerts_status_chk
    CHECK (status IN (
      'open',
      'pending_admin_action',
      'email_sent',
      'email_failed',
      'completed',
      'expired',
      'rate_limited',
      'resolved'
    )),
  CONSTRAINT greenbrain_customer_security_alerts_severity_chk
    CHECK (severity IN ('info', 'warning', 'error'))
);

CREATE INDEX IF NOT EXISTS greenbrain_customer_security_alerts_customer_idx
  ON public.greenbrain_customer_security_alerts (customer_id, last_seen_at DESC);

CREATE INDEX IF NOT EXISTS greenbrain_customer_security_alerts_email_idx
  ON public.greenbrain_customer_security_alerts (lower(email), last_seen_at DESC);

CREATE INDEX IF NOT EXISTS greenbrain_customer_security_alerts_active_idx
  ON public.greenbrain_customer_security_alerts (alert_type, status, last_seen_at DESC)
  WHERE resolved_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS greenbrain_customer_security_alerts_active_reset_email_uidx
  ON public.greenbrain_customer_security_alerts (lower(email), alert_type)
  WHERE resolved_at IS NULL
    AND status IN ('open', 'pending_admin_action', 'email_sent', 'email_failed', 'expired', 'rate_limited');
