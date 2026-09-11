ALTER TABLE public.meals
  ADD COLUMN IF NOT EXISTS calories_kcal numeric,
  ADD COLUMN IF NOT EXISTS portion_weight_g numeric,
  ADD COLUMN IF NOT EXISTS protein_g numeric,
  ADD COLUMN IF NOT EXISTS carbs_g numeric,
  ADD COLUMN IF NOT EXISTS fat_g numeric,
  ADD COLUMN IF NOT EXISTS fiber_g numeric;

COMMENT ON COLUMN public.meals.calories_kcal IS 'Chef-entered calories per listed portion (kcal).';
COMMENT ON COLUMN public.meals.portion_weight_g IS 'Chef-entered cooked portion weight in grams.';
COMMENT ON COLUMN public.meals.protein_g IS 'Chef-entered protein grams per listed portion.';
COMMENT ON COLUMN public.meals.carbs_g IS 'Chef-entered carbohydrate grams per listed portion.';
COMMENT ON COLUMN public.meals.fat_g IS 'Chef-entered fat grams per listed portion.';
COMMENT ON COLUMN public.meals.fiber_g IS 'Chef-entered fiber grams per listed portion.';
