-- Recipe-creator social links on a kitchen card.
-- Chefs paste public Instagram / YouTube / Facebook URLs. Diners open them;
-- HotPotChef does not scrape those platforms or claim follower counts.

ALTER TABLE public.chef_profiles
  ADD COLUMN IF NOT EXISTS instagram_url text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS youtube_url text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS facebook_url text NOT NULL DEFAULT '';

COMMENT ON COLUMN public.chef_profiles.instagram_url IS
  'Public Instagram profile URL the kitchen shares. Empty when not linked.';
COMMENT ON COLUMN public.chef_profiles.youtube_url IS
  'Public YouTube channel or video URL the kitchen shares. Empty when not linked.';
COMMENT ON COLUMN public.chef_profiles.facebook_url IS
  'Public Facebook page URL the kitchen shares. Empty when not linked.';

NOTIFY pgrst, 'reload schema';
