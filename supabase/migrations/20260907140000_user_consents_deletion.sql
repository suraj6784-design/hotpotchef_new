-- User legal consent timestamps and account deletion request marker.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS terms_accepted_at timestamptz,
  ADD COLUMN IF NOT EXISTS privacy_accepted_at timestamptz,
  ADD COLUMN IF NOT EXISTS legal_consent_version text,
  ADD COLUMN IF NOT EXISTS deletion_requested_at timestamptz;

COMMENT ON COLUMN public.users.legal_consent_version IS 'Consent copy version, e.g. 2026-09-07';
