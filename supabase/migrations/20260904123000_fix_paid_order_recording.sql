-- Paid checkouts were refunded when coin/wallet ledger writes failed after Razorpay capture.
-- Record the order first; coin ledger is best-effort and cannot abort a paid insert.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_fee numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS packaging_fee numeric DEFAULT 20,
  ADD COLUMN IF NOT EXISTS tip_amount numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS customer_phone text;

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
  v_packaging numeric := 20;
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
    BEGIN
      v_qty := GREATEST(1, COALESCE(round(NULLIF(v_item->>'quantity', '')::numeric), 1)::int);
    EXCEPTION WHEN OTHERS THEN
      v_qty := 1;
    END;

    BEGIN
      v_price := COALESCE(
        NULLIF(v_item->>'discounted_price', '')::numeric,
        NULLIF(v_item->>'price', '')::numeric,
        NULLIF(v_item->>'base_price', '')::numeric,
        0
      );
    EXCEPTION WHEN OTHERS THEN
      BEGIN
        v_price := COALESCE(NULLIF(v_item->>'price', '')::numeric, 0);
      EXCEPTION WHEN OTHERS THEN
        v_price := 0;
      END;
    END;

    BEGIN
      v_meal_id := NULLIF(COALESCE(v_item->>'source_meal_id', v_item->>'meal_id', v_item->>'mealId'), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_meal_id := NULL;
    END;

    IF v_price <= 0 AND v_meal_id IS NOT NULL THEN
      SELECT COALESCE(price, 0) INTO v_price FROM meals WHERE id = v_meal_id;
    END IF;

    v_food_total := v_food_total + (v_price * v_qty);

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
    v_coins := LEAST(v_coins, v_food_total + COALESCE(p_delivery_fee, 0) + COALESCE(p_tip_amount, 0) + v_packaging);
  END IF;

  v_total := GREATEST(0, v_food_total + COALESCE(p_delivery_fee, 0) + COALESCE(p_tip_amount, 0) + v_packaging - v_coins);

  INSERT INTO orders (
    customer_id, chef_id, items, total_price, status, order_type,
    payment_id, razorpay_order_id, razorpay_signature,
    delivery_address, special_instructions, idempotency_key, coins_applied,
    delivery_fee, packaging_fee, tip_amount, customer_phone, updated_at
  ) VALUES (
    v_customer_id, v_chef_id, p_cart_items::text, v_total, 'Pending Chef Approval', v_order_type,
    p_payment_id, p_razorpay_order_id, p_razorpay_signature,
    p_delivery_address, p_instructions, p_idempotency_key, v_coins,
    COALESCE(p_delivery_fee, 0), v_packaging, COALESCE(p_tip_amount, 0), p_customer_phone, now()
  )
  RETURNING id INTO v_order_id;

  IF v_coins > 0 THEN
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
$$;

GRANT EXECUTE ON FUNCTION public.place_customer_order(
  text, text, text, text, jsonb, boolean, text, uuid, numeric, numeric, text, text, text
) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
