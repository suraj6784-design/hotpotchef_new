-- Guest Home uses PostgREST select of catalog columns. Anon never had
-- SELECT * (column grants). Publish-template fields and hosting_address
-- were missing, so guest `select()` failed and Home showed a wifi empty state.

GRANT SELECT (
  hosting_address,
  cuisine,
  dish_course,
  ingredients,
  allergens,
  prep_minutes,
  cook_minutes,
  serving_size,
  storage_hours,
  video_url,
  delivery_estimate_minutes,
  availability_mode,
  chef_tip,
  is_seasonal,
  allow_notify_when_available
) ON public.meals TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
