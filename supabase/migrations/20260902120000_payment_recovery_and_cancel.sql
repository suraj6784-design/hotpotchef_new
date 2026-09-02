-- P0: persist paid orders, recover orphan charges, restock + refund on cancel.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payment_id text,
  ADD COLUMN IF NOT EXISTS razorpay_order_id text,
  ADD COLUMN IF NOT EXISTS razorpay_signature text,
  ADD COLUMN IF NOT EXISTS delivery_address text,
  ADD COLUMN IF NOT EXISTS special_instructions text,
  ADD COLUMN IF NOT EXISTS idempotency_key text,
  ADD COLUMN IF NOT EXISTS refund_id text,
  ADD COLUMN IF NOT EXISTS refund_status text,
  ADD COLUMN IF NOT EXISTS cancel_reason text,
  ADD COLUMN IF NOT EXISTS coins_applied numeric NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX IF NOT EXISTS orders_idempotency_key_uidx
  ON public.orders (idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS orders_payment_id_uidx
  ON public.orders (payment_id)
  WHERE payment_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.pending_checkouts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  razorpay_order_id text UNIQUE NOT NULL,
  cart_items jsonb NOT NULL,
  delivery_address text,
  instructions text,
  phone text,
  email text,
  apply_coins boolean NOT NULL DEFAULT false,
  tip_amount numeric NOT NULL DEFAULT 0,
  delivery_fee numeric NOT NULL DEFAULT 0,
  amount_paise integer,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.pending_checkouts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pending_checkouts_own ON public.pending_checkouts;
CREATE POLICY pending_checkouts_own ON public.pending_checkouts
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

ALTER TABLE public.pending_checkouts
  ADD COLUMN IF NOT EXISTS amount_paise integer;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pending_checkouts TO authenticated;
GRANT ALL ON public.pending_checkouts TO service_role;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT oid::regprocedure AS sig
    FROM pg_proc
    WHERE proname = 'place_customer_order'
      AND pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
  END LOOP;
END $$;

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
BEGIN
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

  -- JWT callers cannot impersonate another customer. Service-role recovery may pass p_user_id.
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

    IF v_meal_id IS NOT NULL THEN
      UPDATE meals
      SET quantity = quantity - v_qty,
          status = CASE WHEN quantity - v_qty <= 0 THEN 'sold out' ELSE status END
      WHERE id = v_meal_id AND quantity >= v_qty;
      GET DIAGNOSTICS v_updated = ROW_COUNT;
      IF v_updated = 0 THEN
        RAISE EXCEPTION 'One or more meals are no longer available';
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
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.place_customer_order(
  text, text, text, text, jsonb, boolean, text, uuid, numeric, numeric, text, text, text
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.cancel_and_restock_order(
  p_order_id uuid,
  p_reason text DEFAULT 'Cancelled',
  p_chef_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order orders%ROWTYPE;
  v_actor uuid := auth.uid();
  v_items jsonb;
  v_item jsonb;
  v_meal_id uuid;
  v_qty int;
  v_status text;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found');
  END IF;

  v_status := lower(COALESCE(v_order.status, ''));
  IF v_status LIKE '%cancel%' OR v_status LIKE '%reject%' THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_cancelled', true,
      'payment_id', v_order.payment_id,
      'total_price', v_order.total_price,
      'refund_status', v_order.refund_status,
      'refund_id', v_order.refund_id
    );
  END IF;
  IF v_status LIKE '%deliver%' OR v_status LIKE '%complet%' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Delivered orders cannot be cancelled');
  END IF;

  IF v_actor IS NOT NULL THEN
    IF v_actor = v_order.customer_id THEN
      IF v_status LIKE '%prepar%' OR v_status LIKE '%ready%' OR v_status LIKE '%out%' OR v_status LIKE '%assign%' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Kitchen has already started this order');
      END IF;
    ELSIF v_actor = v_order.chef_id OR v_actor = p_chef_id THEN
      NULL;
    ELSE
      RETURN jsonb_build_object('success', false, 'error', 'Not allowed to cancel this order');
    END IF;
  END IF;

  BEGIN
    v_items := v_order.items::jsonb;
  EXCEPTION WHEN OTHERS THEN
    v_items := '[]'::jsonb;
  END;

  IF jsonb_typeof(v_items) = 'array' THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_items)
    LOOP
      v_qty := GREATEST(1, COALESCE(NULLIF(v_item->>'quantity', '')::int, 1));
      BEGIN
        v_meal_id := NULLIF(COALESCE(v_item->>'source_meal_id', v_item->>'meal_id', v_item->>'mealId'), '')::uuid;
      EXCEPTION WHEN OTHERS THEN
        v_meal_id := NULL;
      END;
      IF v_meal_id IS NOT NULL THEN
        UPDATE meals
        SET quantity = COALESCE(quantity, 0) + v_qty,
            status = CASE WHEN lower(COALESCE(status, '')) = 'sold out' THEN 'Available' ELSE status END
        WHERE id = v_meal_id;
      END IF;
    END LOOP;
  END IF;

  IF COALESCE(v_order.coins_applied, 0) > 0 THEN
    UPDATE users
    SET hotpot_coins = COALESCE(hotpot_coins, 0) + v_order.coins_applied
    WHERE id = v_order.customer_id;
    UPDATE wallets
    SET balance = COALESCE(balance, 0) + v_order.coins_applied,
        last_updated = now()
    WHERE user_id = v_order.customer_id;
    INSERT INTO transactions (user_id, amount, transaction_type, description)
    VALUES (v_order.customer_id, v_order.coins_applied, 'refund', 'Coins restored after order cancel');
  END IF;

  UPDATE orders
  SET status = 'Cancelled',
      cancel_reason = p_reason,
      updated_at = now()
  WHERE id = p_order_id;

  RETURN jsonb_build_object(
    'success', true,
    'payment_id', v_order.payment_id,
    'total_price', v_order.total_price,
    'refund_status', v_order.refund_status,
    'refund_id', v_order.refund_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_and_restock_order(uuid, text, uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
