-- Partner KYC photo proofs. Public URLs only; no full Aadhaar digits.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS driving_license_url text,
  ADD COLUMN IF NOT EXISTS insurance_policy_url text,
  ADD COLUMN IF NOT EXISTS aadhaar_proof_url text;

COMMENT ON COLUMN public.users.driving_license_url IS 'Driver DL photo in meal_images; not granted to anon.';
COMMENT ON COLUMN public.users.insurance_policy_url IS 'Vehicle insurance photo; not granted to anon.';
COMMENT ON COLUMN public.users.aadhaar_proof_url IS 'Aadhaar card photo for chef/driver KYC; not granted to anon.';
