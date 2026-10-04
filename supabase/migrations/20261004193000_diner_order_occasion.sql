-- Occasion on new orders, optional meal tags, catering broadcasts, and
-- specialty subscribe cadence.
--
-- Existing order rows are not updated. Orders placed before this column
-- stay null. The insert trigger only stamps rows created after it exists.
-- place_customer_order is unchanged: the occasion rides in cart item JSON.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS occasion text;

COMMENT ON COLUMN public.orders.occasion IS
  'Why the diner ordered: everyday, festive, party, or specialty. Null on orders placed before this column.';

ALTER TABLE public.meals
  ADD COLUMN IF NOT EXISTS occasion text;

COMMENT ON COLUMN public.meals.occasion IS
  'Optional browse tag: everyday, festive, party, or specialty. Empty means the app infers from the dish.';

GRANT SELECT (occasion) ON public.meals TO anon, authenticated;

CREATE INDEX IF NOT EXISTS meals_occasion_available_idx
  ON public.meals (status, occasion)
  WHERE occasion IS NOT NULL;

DO $$
BEGIN
  IF to_regclass('public.customer_requests') IS NOT NULL THEN
    ALTER TABLE public.customer_requests
      ADD COLUMN IF NOT EXISTS occasion text;
    ALTER TABLE public.customer_requests
      ADD COLUMN IF NOT EXISTS occasion_slice text;
    COMMENT ON COLUMN public.customer_requests.occasion IS
      'Broadcast occasion: everyday, festive, party, or specialty. Null on older requests.';
  END IF;
END $$;

ALTER TABLE public.meal_plans
  ADD COLUMN IF NOT EXISTS cadence text NOT NULL DEFAULT 'weekly';

ALTER TABLE public.meal_plans
  ADD COLUMN IF NOT EXISTS month_day smallint;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'meal_plans_cadence_check'
  ) THEN
    ALTER TABLE public.meal_plans
      ADD CONSTRAINT meal_plans_cadence_check
      CHECK (cadence IN ('weekly', 'monthly'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'meal_plans_month_day_check'
  ) THEN
    ALTER TABLE public.meal_plans
      ADD CONSTRAINT meal_plans_month_day_check
      CHECK (month_day IS NULL OR (month_day >= 1 AND month_day <= 28));
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.normalize_order_occasion(p_raw text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(btrim(coalesce(p_raw, '')))
    WHEN 'everyday' THEN 'everyday'
    WHEN 'daily' THEN 'everyday'
    WHEN 'festive' THEN 'festive'
    WHEN 'festival' THEN 'festive'
    WHEN 'festivals' THEN 'festive'
    WHEN 'party' THEN 'party'
    WHEN 'parties' THEN 'party'
    WHEN 'specialty' THEN 'specialty'
    ELSE NULL
  END;
$$;

CREATE OR REPLACE FUNCTION public.order_occasion_from_items(p_items jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_items jsonb := p_items;
  v_item jsonb;
  v_occasion text;
BEGIN
  IF v_items IS NULL THEN
    RETURN NULL;
  END IF;
  IF jsonb_typeof(v_items) = 'string' THEN
    BEGIN
      v_items := (v_items #>> '{}')::jsonb;
    EXCEPTION WHEN OTHERS THEN
      RETURN NULL;
    END;
  END IF;
  IF v_items IS NULL OR jsonb_typeof(v_items) <> 'array' THEN
    RETURN NULL;
  END IF;
  FOR v_item IN SELECT value FROM jsonb_array_elements(v_items)
  LOOP
    v_occasion := public.normalize_order_occasion(COALESCE(
      v_item->>'occasion',
      v_item->'rawMealDetails'->>'occasion',
      v_item->'mealDetails'->>'occasion',
      v_item->'meal_details'->>'occasion'
    ));
    IF v_occasion IS NOT NULL THEN
      RETURN v_occasion;
    END IF;
  END LOOP;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.orders_stamp_occasion()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_occasion text;
BEGIN
  v_occasion := public.normalize_order_occasion(NEW.occasion);
  IF v_occasion IS NULL THEN
    v_occasion := public.order_occasion_from_items(NEW.items);
  END IF;
  NEW.occasion := v_occasion;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_stamp_occasion ON public.orders;
CREATE TRIGGER orders_stamp_occasion
  BEFORE INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.orders_stamp_occasion();

NOTIFY pgrst, 'reload schema';
