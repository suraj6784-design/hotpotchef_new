-- Chef and driver profile screens persist structured address fields on users.
-- The table only had a single `address` text column, so saves failed with PGRST204.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS house_no text,
  ADD COLUMN IF NOT EXISTS street text,
  ADD COLUMN IF NOT EXISTS city text,
  ADD COLUMN IF NOT EXISTS state text,
  ADD COLUMN IF NOT EXISTS pincode text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS emergency_phone text,
  ADD COLUMN IF NOT EXISTS pan_number text,
  ADD COLUMN IF NOT EXISTS blood_group text,
  ADD COLUMN IF NOT EXISTS vehicle_type text,
  ADD COLUMN IF NOT EXISTS vehicle_reg_no text,
  ADD COLUMN IF NOT EXISTS driving_license_no text,
  ADD COLUMN IF NOT EXISTS insurance_policy_no text;

COMMENT ON COLUMN public.users.city IS 'Kitchen or driver city from the in-app profile form.';
COMMENT ON COLUMN public.users.pincode IS '6-digit PIN from the in-app profile form.';

NOTIFY pgrst, 'reload schema';
