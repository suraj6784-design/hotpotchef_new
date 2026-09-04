-- Persist driver online/offline. Live DB may not have driver_profiles yet.

CREATE TABLE IF NOT EXISTS public.driver_profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  is_available boolean NOT NULL DEFAULT true,
  wallet_balance numeric NOT NULL DEFAULT 0,
  total_lifetime_earnings numeric NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.driver_profiles
  ADD COLUMN IF NOT EXISTS is_available boolean NOT NULL DEFAULT true;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'driver_profiles'
      AND column_name = 'is_available'
  ) THEN
    COMMENT ON COLUMN public.driver_profiles.is_available IS
      'Whether the partner is currently accepting new dispatches.';
  END IF;
END $$;

ALTER TABLE public.driver_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS driver_profiles_own ON public.driver_profiles;
CREATE POLICY driver_profiles_own ON public.driver_profiles
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

GRANT SELECT, INSERT, UPDATE ON public.driver_profiles TO authenticated;
GRANT ALL ON public.driver_profiles TO service_role;
