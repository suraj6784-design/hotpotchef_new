-- Paid Home boost: a dish sits first on LIVE OFFERS until midnight IST.

ALTER TABLE public.meals
  ADD COLUMN IF NOT EXISTS boosted_until timestamptz;

CREATE TABLE IF NOT EXISTS public.meal_boosts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meal_id uuid NOT NULL REFERENCES public.meals (id) ON DELETE CASCADE,
  chef_id uuid NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  amount_paise integer NOT NULL DEFAULT 9900 CHECK (amount_paise = 9900),
  status text NOT NULL DEFAULT 'pending',
  starts_at timestamptz,
  ends_at timestamptz,
  razorpay_order_id text,
  razorpay_payment_id text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS meal_boosts_chef_idx
  ON public.meal_boosts (chef_id, created_at DESC);

CREATE INDEX IF NOT EXISTS meals_boosted_until_idx
  ON public.meals (boosted_until)
  WHERE boosted_until IS NOT NULL;

ALTER TABLE public.meal_boosts ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT ON public.meal_boosts TO authenticated;
GRANT ALL ON public.meal_boosts TO service_role;

DROP POLICY IF EXISTS meal_boosts_select ON public.meal_boosts;
CREATE POLICY meal_boosts_select ON public.meal_boosts
  FOR SELECT
  TO authenticated
  USING (auth.uid() = chef_id);

DROP POLICY IF EXISTS meal_boosts_insert ON public.meal_boosts;
CREATE POLICY meal_boosts_insert ON public.meal_boosts
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = chef_id);

NOTIFY pgrst, 'reload schema';
