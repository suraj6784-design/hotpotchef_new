-- Weekly kitchen hours, prep window, promised ETA on orders, late-order coins.

ALTER TABLE public.chef_profiles
  ADD COLUMN IF NOT EXISTS weekly_hours jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS default_prep_minutes integer NOT NULL DEFAULT 30;

ALTER TABLE public.meals
  ADD COLUMN IF NOT EXISTS prep_minutes integer;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS promised_at timestamptz,
  ADD COLUMN IF NOT EXISTS eta_minutes integer,
  ADD COLUMN IF NOT EXISTS late_compensated_at timestamptz,
  ADD COLUMN IF NOT EXISTS late_compensation_coins numeric NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.chef_profiles.weekly_hours IS
  'Mon-Sun windows in 24h HH:MM, Asia/Kolkata. Empty object = no posted hours (is_open still gates).';
COMMENT ON COLUMN public.chef_profiles.default_prep_minutes IS
  'Kitchen prep window used in the diner ETA promise.';
COMMENT ON COLUMN public.orders.promised_at IS
  'Diner-facing arrival promise stamped at place.';

CREATE OR REPLACE FUNCTION public.kitchen_accepting_orders(
  p_chef_id uuid,
  p_at timestamptz DEFAULT now()
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_open boolean;
  v_hours jsonb;
  v_local timestamp;
  v_key text;
  v_day jsonb;
  v_open_m int;
  v_close_m int;
  v_now_m int;
BEGIN
  IF p_chef_id IS NULL THEN
    RETURN true;
  END IF;

  SELECT is_open, weekly_hours
    INTO v_open, v_hours
  FROM public.chef_profiles
  WHERE user_id = p_chef_id;

  IF NOT FOUND THEN
    RETURN true;
  END IF;
  IF v_open IS FALSE THEN
    RETURN false;
  END IF;
  IF v_hours IS NULL OR v_hours = '{}'::jsonb THEN
    RETURN true;
  END IF;

  v_local := p_at AT TIME ZONE 'Asia/Kolkata';
  v_key := (ARRAY['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'])[
    EXTRACT(ISODOW FROM v_local)::int
  ];
  v_day := v_hours -> v_key;
  IF v_day IS NULL OR jsonb_typeof(v_day) <> 'object' THEN
    RETURN false;
  END IF;
  IF COALESCE((v_day->>'closed')::boolean, false) THEN
    RETURN false;
  END IF;

  BEGIN
    v_open_m := (split_part(v_day->>'open', ':', 1)::int * 60)
      + split_part(v_day->>'open', ':', 2)::int;
    v_close_m := (split_part(v_day->>'close', ':', 1)::int * 60)
      + split_part(v_day->>'close', ':', 2)::int;
  EXCEPTION WHEN OTHERS THEN
    RETURN false;
  END;
  IF v_close_m <= v_open_m THEN
    RETURN false;
  END IF;
  v_now_m := EXTRACT(HOUR FROM v_local)::int * 60 + EXTRACT(MINUTE FROM v_local)::int;
  RETURN v_now_m >= v_open_m AND v_now_m < v_close_m;
END;
$$;

REVOKE ALL ON FUNCTION public.kitchen_accepting_orders(uuid, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.kitchen_accepting_orders(uuid, timestamptz) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.stamp_order_time_contract()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_prep int := 30;
  v_travel int := 20;
  v_slot timestamptz;
  v_asap timestamptz;
  v_items jsonb;
BEGIN
  SELECT GREATEST(5, LEAST(240, COALESCE(default_prep_minutes, 30)))
    INTO v_prep
  FROM public.chef_profiles
  WHERE user_id = NEW.chef_id;

  BEGIN
    v_items := NEW.items::jsonb;
    SELECT COALESCE(MAX(GREATEST(5, LEAST(240, m.prep_minutes))), v_prep)
      INTO v_prep
    FROM jsonb_array_elements(
      CASE WHEN jsonb_typeof(v_items) = 'array' THEN v_items ELSE '[]'::jsonb END
    ) elem
    JOIN public.meals m
      ON m.id::text = COALESCE(elem->>'id', elem->>'meal_id', elem->>'mealId');
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  v_travel := GREATEST(8, LEAST(90, COALESCE(NEW.eta_minutes, 20)));
  v_asap := COALESCE(NEW.created_at, now()) + make_interval(mins => v_prep + v_travel);
  v_slot := public.order_prep_slot_start(NEW.items::text, COALESCE(NEW.created_at, now()));

  IF NEW.promised_at IS NULL THEN
    IF v_slot IS NOT NULL AND v_slot > COALESCE(NEW.created_at, now()) THEN
      NEW.promised_at := v_slot;
    ELSE
      NEW.promised_at := v_asap;
    END IF;
  END IF;

  NEW.eta_minutes := GREATEST(
    1,
    CEIL(EXTRACT(EPOCH FROM (NEW.promised_at - COALESCE(NEW.created_at, now()))) / 60.0)
  )::int;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_order_outside_kitchen_hours()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NOT public.kitchen_accepting_orders(NEW.chef_id, now()) THEN
    RAISE EXCEPTION 'This kitchen is closed right now'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_reject_outside_hours ON public.orders;
CREATE TRIGGER orders_reject_outside_hours
  BEFORE INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.reject_order_outside_kitchen_hours();

DROP TRIGGER IF EXISTS orders_stamp_time_contract ON public.orders;
CREATE TRIGGER orders_stamp_time_contract
  BEFORE INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.stamp_order_time_contract();

CREATE OR REPLACE FUNCTION public.apply_late_order_compensation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_done boolean;
  v_late boolean;
  v_coins numeric := 25;
BEGIN
  IF NEW.late_compensated_at IS NOT NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.promised_at IS NULL OR NEW.customer_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_status := lower(btrim(COALESCE(NEW.status, '')));
  v_done := v_status LIKE '%delivered%'
    OR (v_status LIKE '%complet%' AND v_status NOT LIKE '%out%')
    OR v_status LIKE '%cancel%';
  IF NOT v_done THEN
    RETURN NEW;
  END IF;

  v_late := COALESCE(NEW.delivered_at, now()) > (NEW.promised_at + interval '15 minutes');
  IF NOT v_late THEN
    RETURN NEW;
  END IF;

  UPDATE public.users
  SET hotpot_coins = COALESCE(hotpot_coins, 0) + v_coins
  WHERE id = NEW.customer_id;

  NEW.late_compensated_at := now();
  NEW.late_compensation_coins := v_coins;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_late_compensation ON public.orders;
CREATE TRIGGER orders_late_compensation
  BEFORE UPDATE OF status, delivered_at ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.apply_late_order_compensation();

NOTIFY pgrst, 'reload schema';
