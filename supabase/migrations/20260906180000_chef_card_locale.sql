-- Pune-first trust: chef cards can speak Marathi / Hindi.

ALTER TABLE public.chef_profiles
  ADD COLUMN IF NOT EXISTS card_locale text NOT NULL DEFAULT 'en',
  ADD COLUMN IF NOT EXISTS local_kitchen_name text NOT NULL DEFAULT '';

ALTER TABLE public.chef_profiles
  DROP CONSTRAINT IF EXISTS chef_profiles_card_locale_check;

ALTER TABLE public.chef_profiles
  ADD CONSTRAINT chef_profiles_card_locale_check
  CHECK (card_locale IN ('en', 'hi', 'mr'));

NOTIFY pgrst, 'reload schema';
