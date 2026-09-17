-- P1-1: hold the last portion at Razorpay-order creation, not after capture.

CREATE TABLE IF NOT EXISTS public.inventory_holds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  razorpay_order_id text NOT NULL,
  meal_id uuid NOT NULL,
  quantity integer NOT NULL CHECK (quantity > 0),
  status text NOT NULL DEFAULT 'held'
    CHECK (status IN ('held', 'confirmed', 'released')),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS inventory_holds_order_idx
  ON public.inventory_holds (razorpay_order_id);

CREATE INDEX IF NOT EXISTS inventory_holds_open_idx
  ON public.inventory_holds (status, expires_at)
  WHERE status = 'held';

ALTER TABLE public.inventory_holds ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS inventory_holds_own ON public.inventory_holds;
CREATE POLICY inventory_holds_own ON public.inventory_holds
  FOR SELECT
  USING (auth.uid() = user_id);

GRANT SELECT ON public.inventory_holds TO authenticated;
GRANT ALL ON public.inventory_holds TO service_role;

CREATE OR REPLACE FUNCTION public.release_checkout_inventory(
  p_razorpay_order_id text,
  p_force boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_actor uuid := auth.uid();
  v_released int := 0;
BEGIN
  IF p_razorpay_order_id IS NULL OR btrim(p_razorpay_order_id) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Missing Razorpay order id');
  END IF;

  FOR r IN
    SELECT * FROM inventory_holds
    WHERE razorpay_order_id = p_razorpay_order_id
      AND status = 'held'
    FOR UPDATE
  LOOP
    IF v_actor IS NOT NULL AND NOT p_force AND r.user_id <> v_actor THEN
      RETURN jsonb_build_object('success', false, 'error', 'Not allowed to release this hold');
    END IF;

    UPDATE meals
    SET quantity = COALESCE(quantity, 0) + r.quantity,
        status = CASE WHEN lower(COALESCE(status, '')) = 'sold out' THEN 'Available' ELSE status END
    WHERE id = r.meal_id;

    UPDATE inventory_holds SET status = 'released' WHERE id = r.id;
    v_released := v_released + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'released', v_released);
END;
$$;

CREATE OR REPLACE FUNCTION public.expire_checkout_holds()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  oid text;
  n int := 0;
BEGIN
  FOR oid IN
    SELECT DISTINCT razorpay_order_id
    FROM inventory_holds
    WHERE status = 'held' AND expires_at < now()
  LOOP
    PERFORM public.release_checkout_inventory(oid, true);
    n := n + 1;
  END LOOP;
  RETURN jsonb_build_object('success', true, 'expired_orders', n);
END;
$$;

CREATE OR REPLACE FUNCTION public.reserve_checkout_inventory(
  p_razorpay_order_id text,
  p_cart_items jsonb,
  p_user_id uuid DEFAULT NULL,
  p_ttl_minutes integer DEFAULT 15
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid;
  v_item jsonb;
  v_meal_id uuid;
  v_qty int;
  v_map jsonb := '{}'::jsonb;
  v_key text;
  v_needed int;
  v_title text;
  v_updated int;
  v_oid text;
  v_ttl int;
BEGIN
  PERFORM public.expire_checkout_holds();

  IF p_razorpay_order_id IS NULL OR btrim(p_razorpay_order_id) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Missing Razorpay order id');
  END IF;
  IF p_cart_items IS NULL OR jsonb_typeof(p_cart_items) <> 'array' OR jsonb_array_length(p_cart_items) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cart is empty');
  END IF;

  v_user := COALESCE(auth.uid(), p_user_id);
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Customer not found');
  END IF;

  v_ttl := GREATEST(5, LEAST(COALESCE(p_ttl_minutes, 15), 30));

  -- Drop this shopper's abandoned holds so they cannot lock themselves out.
  FOR v_oid IN
    SELECT DISTINCT razorpay_order_id
    FROM inventory_holds
    WHERE user_id = v_user
      AND status = 'held'
      AND razorpay_order_id <> p_razorpay_order_id
  LOOP
    PERFORM public.release_checkout_inventory(v_oid, true);
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM inventory_holds
    WHERE razorpay_order_id = p_razorpay_order_id AND status = 'held'
  ) THEN
    RETURN jsonb_build_object('success', true, 'idempotent', true);
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_cart_items)
  LOOP
    v_qty := GREATEST(1, COALESCE(NULLIF(v_item->>'quantity', '')::int, 1));
    BEGIN
      v_meal_id := NULLIF(COALESCE(v_item->>'source_meal_id', v_item->>'meal_id', v_item->>'mealId'), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_meal_id := NULL;
    END;
    IF v_meal_id IS NULL THEN
      CONTINUE;
    END IF;
    v_needed := COALESCE((v_map->>v_meal_id::text)::int, 0) + v_qty;
    v_map := jsonb_set(v_map, ARRAY[v_meal_id::text], to_jsonb(v_needed));
  END LOOP;

  BEGIN
    FOR v_key, v_needed IN
      SELECT key, value::int FROM jsonb_each_text(v_map)
    LOOP
      v_meal_id := v_key::uuid;

      UPDATE meals
      SET quantity = quantity - v_needed,
          status = CASE WHEN quantity - v_needed <= 0 THEN 'sold out' ELSE status END
      WHERE id = v_meal_id AND quantity >= v_needed;
      GET DIAGNOSTICS v_updated = ROW_COUNT;

      IF v_updated = 0 THEN
        SELECT COALESCE(NULLIF(title, ''), 'This meal') INTO v_title FROM meals WHERE id = v_meal_id;
        RAISE EXCEPTION 'SOLD_OUT:%', COALESCE(v_title, 'This meal');
      END IF;

      INSERT INTO inventory_holds (user_id, razorpay_order_id, meal_id, quantity, status, expires_at)
      VALUES (v_user, p_razorpay_order_id, v_meal_id, v_needed, 'held', now() + make_interval(mins => v_ttl));
    END LOOP;
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM LIKE 'SOLD_OUT:%' THEN
        RETURN jsonb_build_object(
          'success', false,
          'code', 'sold_out',
          'error', 'This meal just sold out. Nothing was charged.'
        );
      END IF;
      RETURN jsonb_build_object('success', false, 'error', SQLERRM);
  END;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.release_checkout_inventory(text, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.expire_checkout_holds() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_checkout_inventory(text, jsonb, uuid, integer) TO authenticated, service_role;

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
AS $$
DECLARE
  v_customer_id uuid;
  v_chef_id uuid;
  v_order_id uuid;
  v_item jsonb;
  v_meal_id uuid;
  v_qty int;
  v_price numeric;
  v_food_total numeric := 0;
  v_coins numeric := 0;
  v_total numeric;
  v_order_type text;
  v_updated int;
  v_has_hold boolean := false;
BEGIN
  PERFORM public.expire_checkout_holds();

  IF p_cart_items IS NULL OR jsonb_typeof(p_cart_items) <> 'array' OR jsonb_array_length(p_cart_items) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cart is empty');
  END IF;

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

  v_customer_id := auth.uid();
  IF v_customer_id IS NULL THEN
    v_customer_id := p_user_id;
  END IF;
  IF v_customer_id IS NULL AND p_customer_email IS NOT NULL THEN
    SELECT id INTO v_customer_id FROM users WHERE email = p_customer_email LIMIT 1;
  END IF;
  IF v_customer_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Customer not found');
  END IF;

  BEGIN
    v_chef_id := NULLIF(COALESCE(p_cart_items->0->>'chef_id', p_cart_items->0->>'chefId'), '')::uuid;
  EXCEPTION WHEN OTHERS THEN
    v_chef_id := NULL;
  END;
  IF v_chef_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Missing chef_id on cart items');
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
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_cart_items)
  LOOP
    v_qty := GREATEST(1, COALESCE(NULLIF(v_item->>'quantity', '')::int, 1));
    v_price := COALESCE(
      NULLIF(v_item->>'discounted_price', '')::numeric,
      NULLIF(v_item->>'price', '')::numeric,
      NULLIF(v_item->>'base_price', '')::numeric,
      0
    );
    BEGIN
      v_meal_id := NULLIF(COALESCE(v_item->>'source_meal_id', v_item->>'meal_id', v_item->>'mealId'), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_meal_id := NULL;
    END;

    IF v_price <= 0 AND v_meal_id IS NOT NULL THEN
      SELECT COALESCE(price, 0) INTO v_price FROM meals WHERE id = v_meal_id;
    END IF;

    v_food_total := v_food_total + (v_price * v_qty);

    -- Stock was already taken when the Razorpay order was created.
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

  IF COALESCE(p_apply_coins, false) THEN
    SELECT COALESCE(hotpot_coins, 0) INTO v_coins FROM users WHERE id = v_customer_id;
    v_coins := LEAST(v_coins, v_food_total + COALESCE(p_delivery_fee, 0) + COALESCE(p_tip_amount, 0) + 20);
  END IF;

  v_total := GREATEST(0, v_food_total + COALESCE(p_delivery_fee, 0) + COALESCE(p_tip_amount, 0) + 20 - v_coins);

  INSERT INTO orders (
    customer_id, chef_id, items, total_price, status, order_type,
    payment_id, razorpay_order_id, razorpay_signature,
    delivery_address, special_instructions, idempotency_key, coins_applied, updated_at
  ) VALUES (
    v_customer_id, v_chef_id, p_cart_items::text, v_total, 'Pending Chef Approval', v_order_type,
    p_payment_id, p_razorpay_order_id, p_razorpay_signature,
    p_delivery_address, p_instructions, p_idempotency_key, v_coins, now()
  )
  RETURNING id INTO v_order_id;

  IF v_coins > 0 THEN
    UPDATE users SET hotpot_coins = GREATEST(0, COALESCE(hotpot_coins, 0) - v_coins) WHERE id = v_customer_id;
    UPDATE wallets SET balance = GREATEST(0, COALESCE(balance, 0) - v_coins), last_updated = now() WHERE user_id = v_customer_id;
    INSERT INTO transactions (user_id, amount, transaction_type, description)
    VALUES (v_customer_id, -v_coins, 'redeem', 'Coins applied at checkout');
  END IF;

  IF p_razorpay_order_id IS NOT NULL THEN
    UPDATE inventory_holds
    SET status = 'confirmed'
    WHERE razorpay_order_id = p_razorpay_order_id AND status = 'held';
    DELETE FROM pending_checkouts WHERE razorpay_order_id = p_razorpay_order_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'order_id', v_order_id, 'total', v_total);
EXCEPTION
  WHEN unique_violation THEN
    SELECT id INTO v_order_id FROM orders
    WHERE (p_idempotency_key IS NOT NULL AND idempotency_key = p_idempotency_key)
       OR (p_payment_id IS NOT NULL AND payment_id = p_payment_id)
    LIMIT 1;
    RETURN jsonb_build_object('success', true, 'order_id', v_order_id, 'idempotent', true);
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
$$;

GRANT EXECUTE ON FUNCTION public.place_customer_order(
  text, text, text, text, jsonb, boolean, text, uuid, numeric, numeric, text, text, text
) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
