-- Guest Home uses an explicit meals column list. select * fails for anon because
-- payout, transfer, FSSAI, and legacy order columns are revoked, and PostgREST
-- rejects the whole request (42501). Public menu fields added after that revoke
-- were also missing for anon, so the catalog filter (hosting address, prep,
-- cuisine, allergens) could not run. Keep customer PII and payout columns revoked.

GRANT SELECT (
  hosting_address,
  cuisine,
  prep_minutes,
  allergens,
  ingredients,
  video_url,
  availability_mode,
  dish_course,
  cook_minutes,
  serving_size,
  storage_hours,
  delivery_estimate_minutes,
  chef_tip,
  is_seasonal,
  allow_notify_when_available
) ON public.meals TO anon;
