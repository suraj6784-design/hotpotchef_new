-- Standing weekly tiffin plans. Diners confirm each day's box in the cart;
-- we do not auto-charge.

CREATE TABLE IF NOT EXISTS public.meal_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  chef_id uuid NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  meal_id uuid,
  meal_title text NOT NULL DEFAULT 'Home meal',
  chef_name text NOT NULL DEFAULT 'Home kitchen',
  quantity integer NOT NULL DEFAULT 1 CHECK (quantity >= 1 AND quantity <= 20),
  weekdays smallint[] NOT NULL DEFAULT '{}',
  time_slot text NOT NULL DEFAULT 'ASAP',
  service_type text NOT NULL DEFAULT 'Delivery Partner',
  meal_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS meal_plans_customer_idx
  ON public.meal_plans (customer_id, is_active);

CREATE UNIQUE INDEX IF NOT EXISTS meal_plans_one_active_per_meal
  ON public.meal_plans (customer_id, meal_id)
  WHERE is_active AND meal_id IS NOT NULL;

ALTER TABLE public.meal_plans ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.meal_plans TO authenticated;
GRANT ALL ON public.meal_plans TO service_role;

DROP POLICY IF EXISTS meal_plans_select ON public.meal_plans;
CREATE POLICY meal_plans_select ON public.meal_plans
  FOR SELECT
  TO authenticated
  USING (auth.uid() = customer_id OR auth.uid() = chef_id);

DROP POLICY IF EXISTS meal_plans_insert ON public.meal_plans;
CREATE POLICY meal_plans_insert ON public.meal_plans
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = customer_id);

DROP POLICY IF EXISTS meal_plans_update ON public.meal_plans;
CREATE POLICY meal_plans_update ON public.meal_plans
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = customer_id)
  WITH CHECK (auth.uid() = customer_id);

DROP POLICY IF EXISTS meal_plans_delete ON public.meal_plans;
CREATE POLICY meal_plans_delete ON public.meal_plans
  FOR DELETE
  TO authenticated
  USING (auth.uid() = customer_id);

NOTIFY pgrst, 'reload schema';
