-- Customer delivery: ₹0 on food ₹199+; members always ₹0.
-- Packaging: ₹10 under ₹199 food, ₹20 at/above. Admin-controlled membership flash.

CREATE TABLE IF NOT EXISTS public.membership_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  list_price_inr numeric NOT NULL DEFAULT 149,
  offer_price_inr numeric NOT NULL DEFAULT 149,
  duration_days integer NOT NULL DEFAULT 90,
  flash_enabled boolean NOT NULL DEFAULT false,
  flash_label text,
  flash_starts_at timestamptz,
  flash_ends_at timestamptz,
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  waives_delivery boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.diner_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  plan_id uuid REFERENCES public.membership_plans(id) ON DELETE SET NULL,
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'active',
  amount_paid numeric NOT NULL DEFAULT 0,
  granted_by uuid,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.diner_membership_leads (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  plan_id uuid REFERENCES public.membership_plans(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS diner_memberships_user_active_idx
  ON public.diner_memberships (user_id, status, ends_at DESC);

ALTER TABLE public.membership_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diner_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diner_membership_leads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS membership_plans_read ON public.membership_plans;
CREATE POLICY membership_plans_read ON public.membership_plans
  FOR SELECT TO authenticated
  USING (is_active OR public.is_platform_ops());

DROP POLICY IF EXISTS membership_plans_write ON public.membership_plans;
CREATE POLICY membership_plans_write ON public.membership_plans
  FOR ALL TO authenticated
  USING (public.is_platform_ops())
  WITH CHECK (public.is_platform_ops());

DROP POLICY IF EXISTS diner_memberships_read ON public.diner_memberships;
CREATE POLICY diner_memberships_read ON public.diner_memberships
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_platform_ops());

DROP POLICY IF EXISTS diner_memberships_ops_write ON public.diner_memberships;
CREATE POLICY diner_memberships_ops_write ON public.diner_memberships
  FOR ALL TO authenticated
  USING (public.is_platform_ops())
  WITH CHECK (public.is_platform_ops());

DROP POLICY IF EXISTS diner_membership_leads_own ON public.diner_membership_leads;
CREATE POLICY diner_membership_leads_own ON public.diner_membership_leads
  FOR ALL TO authenticated
  USING (user_id = auth.uid() OR public.is_platform_ops())
  WITH CHECK (user_id = auth.uid() OR public.is_platform_ops());

INSERT INTO public.membership_plans (
  name, list_price_inr, offer_price_inr, duration_days,
  flash_enabled, flash_label, flash_starts_at, flash_ends_at, sort_order
)
SELECT
  'HotPotChef Member', 149, 1, 90,
  true, '₹1 for 3 months', now(), now() + interval '30 days', 0
WHERE NOT EXISTS (SELECT 1 FROM public.membership_plans);

CREATE OR REPLACE FUNCTION public.diner_membership_is_active(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.diner_memberships m
    JOIN public.membership_plans p ON p.id = m.plan_id
    WHERE m.user_id = p_user_id
      AND m.status = 'active'
      AND m.ends_at > now()
      AND COALESCE(p.waives_delivery, true)
  );
$$;

CREATE OR REPLACE FUNCTION public.diner_membership_waives_delivery()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.diner_membership_is_active(auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.diner_flash_membership_offer()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan public.membership_plans%ROWTYPE;
  v_member boolean;
BEGIN
  v_member := public.diner_membership_is_active(auth.uid());
  SELECT * INTO v_plan
  FROM public.membership_plans
  WHERE is_active
    AND flash_enabled
    AND (flash_starts_at IS NULL OR flash_starts_at <= now())
    AND (flash_ends_at IS NULL OR flash_ends_at >= now())
  ORDER BY sort_order, offer_price_inr
  LIMIT 1;

  IF NOT FOUND THEN
    SELECT * INTO v_plan
    FROM public.membership_plans
    WHERE is_active
    ORDER BY sort_order
    LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('active_member', v_member);
  END IF;

  RETURN jsonb_build_object(
    'active_member', v_member,
    'plan_id', v_plan.id,
    'name', v_plan.name,
    'list_price_inr', v_plan.list_price_inr,
    'offer_price_inr', v_plan.offer_price_inr,
    'duration_days', v_plan.duration_days,
    'flash_enabled', v_plan.flash_enabled
      AND (v_plan.flash_starts_at IS NULL OR v_plan.flash_starts_at <= now())
      AND (v_plan.flash_ends_at IS NULL OR v_plan.flash_ends_at >= now()),
    'flash_label', COALESCE(v_plan.flash_label, ''),
    'waives_delivery', v_plan.waives_delivery
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.diner_interest_in_membership(p_plan_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Sign in first');
  END IF;
  INSERT INTO public.diner_membership_leads (user_id, plan_id)
  VALUES (auth.uid(), p_plan_id)
  ON CONFLICT (user_id) DO UPDATE SET plan_id = EXCLUDED.plan_id, created_at = now();
  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_grant_membership(
  p_email text,
  p_plan_id uuid DEFAULT NULL,
  p_days integer DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid;
  v_plan public.membership_plans%ROWTYPE;
  v_days integer;
BEGIN
  IF NOT public.is_platform_ops() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin only');
  END IF;

  SELECT id INTO v_user
  FROM public.users
  WHERE lower(email) = lower(trim(p_email))
  LIMIT 1;
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Customer not found');
  END IF;

  IF p_plan_id IS NOT NULL THEN
    SELECT * INTO v_plan FROM public.membership_plans WHERE id = p_plan_id;
  ELSE
    SELECT * INTO v_plan FROM public.membership_plans WHERE is_active ORDER BY sort_order LIMIT 1;
  END IF;
  IF v_plan.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'No membership plan');
  END IF;

  v_days := GREATEST(1, COALESCE(p_days, v_plan.duration_days, 90));

  INSERT INTO public.diner_memberships (
    user_id, plan_id, starts_at, ends_at, status, amount_paid, granted_by, note
  ) VALUES (
    v_user, v_plan.id, now(), now() + make_interval(days => v_days), 'active',
    COALESCE(v_plan.offer_price_inr, 0), auth.uid(), p_note
  );

  RETURN jsonb_build_object('success', true, 'user_id', v_user, 'days', v_days);
END;
$$;

CREATE OR REPLACE FUNCTION public.packaging_fee_from_food_total(p_food numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN COALESCE(p_food, 0) <= 0 THEN 0
    WHEN p_food >= 199 THEN 20
    ELSE 10
  END;
$$;

CREATE OR REPLACE FUNCTION public.packaging_fee_for_cart(
  p_user_id uuid,
  p_cart_items jsonb
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item jsonb;
  v_qty int;
  v_unit numeric;
  v_food numeric := 0;
BEGIN
  IF p_cart_items IS NULL OR jsonb_typeof(p_cart_items) <> 'array' OR jsonb_array_length(p_cart_items) = 0 THEN
    RETURN 0;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_cart_items)
  LOOP
    BEGIN
      v_qty := GREATEST(1, COALESCE(round(NULLIF(v_item->>'quantity', '')::numeric), 1)::int);
    EXCEPTION WHEN OTHERS THEN
      v_qty := 1;
    END;
    BEGIN
      v_unit := COALESCE(
        NULLIF(v_item->>'discounted_price', '')::numeric,
        NULLIF(v_item->>'price', '')::numeric,
        NULLIF(v_item->>'base_price', '')::numeric,
        0
      );
    EXCEPTION WHEN OTHERS THEN
      v_unit := 0;
    END;
    v_food := v_food + (GREATEST(v_unit, 0) * v_qty);
  END LOOP;

  RETURN public.packaging_fee_from_food_total(v_food);
END;
$$;

CREATE OR REPLACE FUNCTION public.calculate_cart_total(p_items jsonb, p_user_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_item jsonb;
  v_qty int;
  v_unit numeric;
  v_food numeric := 0;
  v_packaging numeric := 0;
BEGIN
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RETURN jsonb_build_object(
      'items_total', 0,
      'item_total', 0,
      'subtotal', 0,
      'packaging_fee', 0,
      'total', 0
    );
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    BEGIN
      v_qty := GREATEST(1, COALESCE(round(NULLIF(v_item->>'quantity', '')::numeric), 1)::int);
    EXCEPTION WHEN OTHERS THEN
      v_qty := 1;
    END;
    BEGIN
      v_unit := COALESCE(
        NULLIF(v_item->>'discounted_price', '')::numeric,
        NULLIF(v_item->>'price', '')::numeric,
        NULLIF(v_item->>'base_price', '')::numeric,
        0
      );
    EXCEPTION WHEN OTHERS THEN
      v_unit := 0;
    END;
    v_food := v_food + (GREATEST(v_unit, 0) * v_qty);
  END LOOP;

  v_packaging := public.packaging_fee_from_food_total(v_food);

  RETURN jsonb_build_object(
    'items_total', ROUND(v_food, 2),
    'item_total', ROUND(v_food, 2),
    'subtotal', ROUND(v_food, 2),
    'packaging_fee', v_packaging,
    'total', ROUND(v_food + v_packaging, 2)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.quote_customer_delivery_fee(
  p_items jsonb,
  p_drop_lat numeric DEFAULT NULL,
  p_drop_lng numeric DEFAULT NULL,
  p_user_id uuid DEFAULT NULL,
  p_food_total numeric DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_distance numeric;
  v_food numeric;
  v_uid uuid;
BEGIN
  v_distance := public.quote_checkout_delivery_fee(p_items, p_drop_lat, p_drop_lng);
  IF v_distance <= 0 THEN
    RETURN 0;
  END IF;

  v_uid := COALESCE(p_user_id, auth.uid());
  IF v_uid IS NOT NULL AND public.diner_membership_is_active(v_uid) THEN
    RETURN 0;
  END IF;

  v_food := COALESCE(p_food_total, (public.calculate_cart_total(p_items, v_uid)->>'items_total')::numeric, 0);
  IF v_food >= 199 THEN
    RETURN 0;
  END IF;

  RETURN ROUND(v_distance, 2);
END;
$$;

CREATE OR REPLACE FUNCTION public.place_customer_order(
  p_customer_email text,
  p_customer_phone text,
  p_delivery_address text,
  p_instructions text,
  p_cart_items jsonb,
  p_apply_coins boolean,
  p_idempotency_key text,
  p_user_id uuid DEFAULT NULL,
  p_tip_amount numeric DEFAULT 0,
  p_delivery_fee numeric DEFAULT 0,
  p_payment_id text DEFAULT NULL,
  p_razorpay_order_id text DEFAULT NULL,
  p_razorpay_signature text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_customer_id uuid;
  v_chef_id uuid;
  v_order_id uuid;
  v_item jsonb;
  v_meal_id uuid;
  v_qty int;
  v_price numeric;
  v_line numeric;
  v_food_total numeric := 0;
  v_coins numeric := 0;
  v_held_coins numeric;
  v_total numeric;
  v_margin numeric := 0;
  v_order_type text;
  v_updated int;
  v_has_hold boolean := false;
  v_packaging numeric := 20;
  v_coins_ok boolean := true;
  v_kitchen_open boolean;
  v_delivery numeric := 0;
  v_tip numeric := 0;
  v_drop_lat numeric;
  v_drop_lng numeric;
  v_pending_tip numeric;
  v_coins_payment boolean := false;
  v_has_pending boolean := false;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Orders must be placed by the payment service');
  END IF;

  PERFORM public.expire_checkout_holds();

  IF p_cart_items IS NULL OR jsonb_typeof(p_cart_items) <> 'array' OR jsonb_array_length(p_cart_items) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cart is empty');
  END IF;

  v_coins_payment := p_payment_id IS NOT NULL AND p_payment_id LIKE 'coins_%';

  IF p_idempotency_key IS NOT NULL THEN
    SELECT id INTO v_order_id FROM orders WHERE idempotency_key = p_idempotency_key LIMIT 1;
    IF v_order_id IS NOT NULL THEN
      RETURN jsonb_build_object('success', true, 'order_id', v_order_id, 'idempotent', true);
    END IF;
  END IF;

  IF p_payment_id IS NOT NULL THEN
    SELECT id INTO v_order_id FROM orders WHERE payment_id = p_payment_id LIMIT 1;
    IF v_order_id IS NOT NULL THEN
      RETURN jsonb_build_object('success', true, 'order_id', v_order_id, 'idempotent', true);
    END IF;
  END IF;

  IF p_razorpay_order_id IS NOT NULL AND length(trim(p_razorpay_order_id)) > 0 THEN
    SELECT id INTO v_order_id
    FROM orders
    WHERE razorpay_order_id = p_razorpay_order_id
    LIMIT 1;
    IF v_order_id IS NOT NULL THEN
      RETURN jsonb_build_object('success', true, 'order_id', v_order_id, 'idempotent', true);
    END IF;
    SELECT EXISTS (
      SELECT 1 FROM pending_checkouts WHERE razorpay_order_id = p_razorpay_order_id
    ) INTO v_has_pending;
  END IF;

  IF NOT v_coins_payment THEN
    IF p_razorpay_order_id IS NULL OR length(trim(p_razorpay_order_id)) = 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'Missing payment order');
    END IF;
    IF NOT v_has_pending AND coalesce(p_razorpay_signature, '') = '' THEN
      RETURN jsonb_build_object('success', false, 'error', 'No verified checkout for this payment');
    END IF;
  END IF;

  v_customer_id := p_user_id;
  IF v_customer_id IS NULL AND p_customer_email IS NOT NULL THEN
    SELECT id INTO v_customer_id FROM users WHERE email = p_customer_email LIMIT 1;
  END IF;
  IF v_customer_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Customer not found');
  END IF;

  BEGIN
    v_chef_id := NULLIF(COALESCE(
      p_cart_items->0->>'chef_id',
      p_cart_items->0->>'chefId',
      p_cart_items->0->'mealDetails'->>'chef_id',
      p_cart_items->0->'rawMealDetails'->>'chef_id',
      p_cart_items->0->'meal_details'->>'chef_id'
    ), '')::uuid;
  EXCEPTION WHEN OTHERS THEN
    v_chef_id := NULL;
  END;
  IF v_chef_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Missing chef_id on cart items');
  END IF;

  SELECT is_open INTO v_kitchen_open
  FROM chef_profiles
  WHERE user_id = v_chef_id;
  IF v_kitchen_open IS FALSE THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'kitchen_closed',
      'error', 'This kitchen is closed right now'
    );
  END IF;

  v_tip := GREATEST(0, LEAST(500, COALESCE(p_tip_amount, 0)));
  IF p_razorpay_order_id IS NOT NULL THEN
    SELECT dropoff_lat, dropoff_lng, tip_amount
      INTO v_drop_lat, v_drop_lng, v_pending_tip
    FROM pending_checkouts
    WHERE razorpay_order_id = p_razorpay_order_id;
    IF v_pending_tip IS NOT NULL THEN
      v_tip := GREATEST(0, LEAST(500, v_pending_tip));
    END IF;
  END IF;

  v_order_type := COALESCE(
    p_cart_items->0->>'selected_service_type',
    p_cart_items->0->>'service_type',
    p_cart_items->0->>'serviceType',
    'Delivery'
  );

  IF p_razorpay_order_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM inventory_holds
      WHERE razorpay_order_id = p_razorpay_order_id AND status = 'held'
    ) INTO v_has_hold;
    SELECT amount INTO v_held_coins
    FROM coin_holds
    WHERE razorpay_order_id = p_razorpay_order_id AND status = 'held'
    LIMIT 1;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_cart_items)
  LOOP
    BEGIN
      v_qty := GREATEST(1, COALESCE(round(NULLIF(v_item->>'quantity', '')::numeric), 1)::int);
    EXCEPTION WHEN OTHERS THEN
      v_qty := 1;
    END;

    BEGIN
      v_meal_id := NULLIF(COALESCE(v_item->>'source_meal_id', v_item->>'meal_id', v_item->>'mealId', v_item->>'id'), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_meal_id := NULL;
    END;

    v_line := public.catalog_line_total(v_item);
    IF v_line IS NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'sold_out', 'error', 'A plate is no longer on the menu');
    END IF;
    v_price := v_line / v_qty;

    IF COALESCE(v_item->>'accepts_hotpot_coins', 'true') IN ('false', 'f') THEN
      v_coins_ok := false;
    END IF;

    v_food_total := v_food_total + v_line;

    IF NOT v_has_hold AND v_meal_id IS NOT NULL THEN
      UPDATE meals
      SET quantity = quantity - v_qty,
          status = CASE WHEN quantity - v_qty <= 0 THEN 'sold out' ELSE status END
      WHERE id = v_meal_id AND quantity >= v_qty;
      GET DIAGNOSTICS v_updated = ROW_COUNT;
      IF v_updated = 0 THEN
        RAISE EXCEPTION 'SOLD_OUT:This meal just sold out';
      END IF;
    END IF;
  END LOOP;

  v_packaging := public.packaging_fee_from_food_total(v_food_total);
  v_delivery := public.quote_customer_delivery_fee(
    p_cart_items, v_drop_lat, v_drop_lng, v_customer_id, v_food_total
  );

  IF v_held_coins IS NOT NULL THEN
    v_coins := GREATEST(0, v_held_coins);
  ELSIF COALESCE(p_apply_coins, false) AND v_coins_ok THEN
    SELECT COALESCE(hotpot_coins, 0) INTO v_coins FROM users WHERE id = v_customer_id;
    v_coins := LEAST(v_coins, v_food_total + v_delivery + v_tip + v_packaging);
  END IF;

  v_total := GREATEST(0, v_food_total + v_delivery + v_tip + v_packaging - v_coins);
  IF v_coins_payment AND v_total >= 1 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'HotPot Coins do not cover this order'
    );
  END IF;
  v_margin := ROUND(0.15 * GREATEST(0, v_food_total + v_packaging), 2);

  INSERT INTO orders (
    customer_id, chef_id, items, total_price, status, order_type,
    payment_id, razorpay_order_id, razorpay_signature,
    delivery_address, special_instructions, idempotency_key, coins_applied,
    delivery_fee, packaging_fee, tip_amount, customer_phone, platform_margin, updated_at
  ) VALUES (
    v_customer_id, v_chef_id, p_cart_items::text, v_total, 'Pending Chef Approval', v_order_type,
    p_payment_id, p_razorpay_order_id, p_razorpay_signature,
    p_delivery_address, p_instructions, p_idempotency_key, v_coins,
    v_delivery, v_packaging, v_tip, p_customer_phone, v_margin, now()
  )
  RETURNING id INTO v_order_id;

  IF v_coins > 0 AND v_held_coins IS NULL THEN
    UPDATE users
    SET hotpot_coins = GREATEST(0, COALESCE(hotpot_coins, 0) - v_coins)
    WHERE id = v_customer_id;

    BEGIN
      UPDATE wallets
      SET balance = GREATEST(0, COALESCE(balance, 0) - v_coins),
          last_updated = now()
      WHERE user_id = v_customer_id;
    EXCEPTION WHEN undefined_column THEN
      UPDATE wallets
      SET balance = GREATEST(0, COALESCE(balance, 0) - v_coins)
      WHERE user_id = v_customer_id;
    WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  IF v_coins > 0 THEN
    BEGIN
      INSERT INTO transactions (user_id, amount, transaction_type, description)
      VALUES (v_customer_id, v_coins, 'debit', 'Coins applied at checkout');
    EXCEPTION WHEN OTHERS THEN
      BEGIN
        INSERT INTO transactions (user_id, amount, transaction_type, description)
        VALUES (v_customer_id, -v_coins, 'redeem', 'Coins applied at checkout');
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END;
  END IF;

  IF p_razorpay_order_id IS NOT NULL THEN
    UPDATE inventory_holds
    SET status = 'confirmed'
    WHERE razorpay_order_id = p_razorpay_order_id AND status = 'held';
    UPDATE coin_holds
    SET status = 'confirmed'
    WHERE razorpay_order_id = p_razorpay_order_id AND status = 'held';
    DELETE FROM pending_checkouts WHERE razorpay_order_id = p_razorpay_order_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'order_id', v_order_id, 'total', v_total, 'platform_margin', v_margin);
EXCEPTION
  WHEN unique_violation THEN
    SELECT id INTO v_order_id FROM orders
    WHERE (p_idempotency_key IS NOT NULL AND idempotency_key = p_idempotency_key)
       OR (p_payment_id IS NOT NULL AND payment_id = p_payment_id)
       OR (p_razorpay_order_id IS NOT NULL AND razorpay_order_id = p_razorpay_order_id)
    LIMIT 1;
    RETURN jsonb_build_object('success', true, 'order_id', v_order_id, 'idempotent', true);
  WHEN undefined_column THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
  WHEN OTHERS THEN
    IF SQLERRM LIKE 'SOLD_OUT:%' THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'sold_out',
        'error', 'This meal just sold out'
      );
    END IF;
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;

REVOKE ALL ON FUNCTION public.diner_membership_is_active(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.diner_membership_is_active(uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.diner_membership_waives_delivery() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.diner_membership_waives_delivery() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.diner_flash_membership_offer() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.diner_flash_membership_offer() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.diner_interest_in_membership(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.diner_interest_in_membership(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_grant_membership(text, uuid, integer, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_grant_membership(text, uuid, integer, text) TO authenticated;
REVOKE ALL ON FUNCTION public.packaging_fee_from_food_total(numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.packaging_fee_from_food_total(numeric) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.packaging_fee_for_cart(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.packaging_fee_for_cart(uuid, jsonb) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.calculate_cart_total(jsonb, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.calculate_cart_total(jsonb, uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.quote_customer_delivery_fee(jsonb, numeric, numeric, uuid, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quote_customer_delivery_fee(jsonb, numeric, numeric, uuid, numeric) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.place_customer_order(text, text, text, text, jsonb, boolean, text, uuid, numeric, numeric, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.place_customer_order(text, text, text, text, jsonb, boolean, text, uuid, numeric, numeric, text, text, text) TO service_role;

NOTIFY pgrst, 'reload schema';
