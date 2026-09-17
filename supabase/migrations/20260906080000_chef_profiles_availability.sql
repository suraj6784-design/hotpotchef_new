-- Live DB never had chef_profiles, so Online/Offline could not persist.
-- Missing row = kitchen open. Offline only hides new demand; accepted
-- orders stay on the chef hub to finish or cancel.

CREATE TABLE IF NOT EXISTS public.chef_profiles (
  user_id uuid PRIMARY KEY REFERENCES public.users (id) ON DELETE CASCADE,
  is_open boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.chef_profiles
  ADD COLUMN IF NOT EXISTS is_open boolean NOT NULL DEFAULT true;

ALTER TABLE public.chef_profiles
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

INSERT INTO public.chef_profiles (user_id, is_open)
SELECT u.id, true
FROM public.users u
WHERE lower(btrim(u.role::text)) IN ('chef', 'cook')
ON CONFLICT (user_id) DO NOTHING;

ALTER TABLE public.chef_profiles ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON public.chef_profiles TO authenticated;
GRANT ALL ON public.chef_profiles TO service_role;

DROP POLICY IF EXISTS chef_profiles_select ON public.chef_profiles;
CREATE POLICY chef_profiles_select ON public.chef_profiles
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS chef_profiles_write ON public.chef_profiles;
CREATE POLICY chef_profiles_write ON public.chef_profiles
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

NOTIFY pgrst, 'reload schema';
