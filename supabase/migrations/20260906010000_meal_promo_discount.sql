-- Extra promo that stacks on the meal offer after the customer enters promo_code.
ALTER TABLE public.meals
  ADD COLUMN IF NOT EXISTS promo_discount_type text,
  ADD COLUMN IF NOT EXISTS promo_discount_value numeric;

COMMENT ON COLUMN public.meals.promo_discount_type IS
  'percentage or flat extra applied after a matching promo_code; stacks on offer_type';
COMMENT ON COLUMN public.meals.promo_discount_value IS
  'Extra promo amount: percent (0-90) or rupees off the dish line';
