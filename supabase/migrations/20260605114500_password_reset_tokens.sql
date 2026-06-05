-- Password reset token support.
-- Tokens are never stored in clear text: only token_hash is stored.
-- This table supports both self-service reset requests and admin/dev generated reset links.

CREATE TABLE IF NOT EXISTS public.greenbrain_user_password_reset_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES public.greenbrain_users(id) ON DELETE SET NULL,
  email text NOT NULL,
  token_hash text NOT NULL UNIQUE,
  source text NOT NULL DEFAULT 'self_service',
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  revoked_at timestamptz,
  created_by_user_id uuid REFERENCES public.greenbrain_users(id) ON DELETE SET NULL,
  requested_ip text,
  requested_user_agent text,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT greenbrain_password_reset_tokens_status_chk
    CHECK (status IN ('active', 'used', 'expired', 'revoked')),
  CONSTRAINT greenbrain_password_reset_tokens_source_chk
    CHECK (source IN ('self_service', 'admin', 'dev')),
  CONSTRAINT greenbrain_password_reset_tokens_expiry_chk
    CHECK (expires_at > created_at)
);

CREATE INDEX IF NOT EXISTS greenbrain_password_reset_tokens_user_idx
  ON public.greenbrain_user_password_reset_tokens (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS greenbrain_password_reset_tokens_email_idx
  ON public.greenbrain_user_password_reset_tokens (lower(email), created_at DESC);

CREATE INDEX IF NOT EXISTS greenbrain_password_reset_tokens_active_hash_idx
  ON public.greenbrain_user_password_reset_tokens (token_hash)
  WHERE status = 'active' AND used_at IS NULL AND revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS greenbrain_password_reset_tokens_active_email_idx
  ON public.greenbrain_user_password_reset_tokens (lower(email), expires_at DESC)
  WHERE status = 'active' AND used_at IS NULL AND revoked_at IS NULL;
