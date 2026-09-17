-- Dish/meal publishing template fields for kitchen cards.

ALTER TABLE public.meals
  ADD COLUMN IF NOT EXISTS cuisine text,
  ADD COLUMN IF NOT EXISTS dish_course text,
  ADD COLUMN IF NOT EXISTS ingredients text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS allergens text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS prep_minutes integer,
  ADD COLUMN IF NOT EXISTS cook_minutes integer,
  ADD COLUMN IF NOT EXISTS serving_size text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS storage_hours integer,
  ADD COLUMN IF NOT EXISTS video_url text,
  ADD COLUMN IF NOT EXISTS delivery_estimate_minutes integer,
  ADD COLUMN IF NOT EXISTS availability_mode text NOT NULL DEFAULT 'live',
  ADD COLUMN IF NOT EXISTS chef_tip text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS is_seasonal boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS allow_notify_when_available boolean NOT NULL DEFAULT true;

ALTER TABLE public.meals
  DROP CONSTRAINT IF EXISTS meals_availability_mode_check;
ALTER TABLE public.meals
  ADD CONSTRAINT meals_availability_mode_check
  CHECK (availability_mode IN ('live', 'preorder'));

COMMENT ON COLUMN public.meals.cuisine IS 'Kitchen cuisine type (Indian, Italian, Fusion, regional, etc).';
COMMENT ON COLUMN public.meals.dish_course IS 'Starter, Main Course, Dessert, or Snack.';
COMMENT ON COLUMN public.meals.ingredients IS 'Short key-ingredient snapshot for diners.';
COMMENT ON COLUMN public.meals.allergens IS 'Highlighted allergens such as nuts, dairy, gluten.';
COMMENT ON COLUMN public.meals.video_url IS 'Optional plating or cooking clip URL.';
COMMENT ON COLUMN public.meals.availability_mode IS 'live = order now; preorder = scheduled slot.';
COMMENT ON COLUMN public.meals.chef_tip IS 'Optional personal note from the kitchen.';
COMMENT ON COLUMN public.meals.allow_notify_when_available IS 'When true, diners may request a ping when the plate is back.';

NOTIFY pgrst, 'reload schema';
