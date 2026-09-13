-- Critical checkout / kitchen / loyalty RPCs.
--
-- Signatures match Flutter + edge call sites:
--   calculate_cart_total(p_items [, p_user_id])
--   place_customer_order(p_customer_email, p_customer_phone, p_delivery_address,
--     p_instructions, p_cart_items, p_apply_coins, p_tip_amount, p_delivery_fee,
--     p_payment_id, p_razorpay_order_id, p_razorpay_signature, p_idempotency_key,
--     p_user_id)
--   cancel_and_restock_order(p_order_id, p_chef_id, p_reason)
--   claim_daily_streak(p_user_id)
--
-- Function bodies: recovered from prior repo history (same project
-- tpcykyaumvqtwhuiiomg) and adjusted so they do not contradict this repo's
-- clients. The later "service_role-only place_customer_order" hardening is
-- NOT applied — CheckoutScreen still calls the RPC with the user JWT after
-- Razorpay success.
--
-- reconstructed from call sites — verify against hosted project before production

-- ---------------------------------------------------------------------------
-- Inventory hold helpers (place_customer_order calls expire_checkout_holds)
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Packaging + catalog line pricing
-- Gold Foodie: ₹0 packaging. Everyone else: ₹20 (Flutter default).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.packaging_fee_for_loyalty(p_user_id uuid)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_tier text;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN 20;
  END IF;

  SELECT loyalty_tier INTO v_tier
  FROM public.user_gamification
  WHERE user_id = p_user_id;

  IF lower(COALESCE(v_tier, '')) LIKE '%gold%' THEN
    RETURN 0;
  END IF;
  RETURN 20;
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
  v_base numeric := public.packaging_fee_for_loyalty(p_user_id);
  v_item jsonb;
  v_hot int := 0;
  v_hamper int := 0;
  v_shelf int := 0;
  v_flag text;
  v_kind text;
  v_cat text;
BEGIN
  IF p_cart_items IS NULL OR jsonb_typeof(p_cart_items) <> 'array' OR jsonb_array_length(p_cart_items) = 0 THEN
    RETURN v_base;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_cart_items)
  LOOP
    v_flag := lower(coalesce(
      v_item->>'is_shelf_item',
      v_item->'rawMealDetails'->>'is_shelf_item',
      v_item->'mealDetails'->>'is_shelf_item',
      ''
    ));
    v_kind := lower(coalesce(
      v_item->>'shelf_kind',
      v_item->'rawMealDetails'->>'shelf_kind',
      ''
    ));
    v_cat := lower(coalesce(
      v_item->>'category',
      v_item->'rawMealDetails'->>'category',
      v_item->'mealDetails'->>'category',
      ''
    ));
    IF v_flag IN ('true', 't', '1', 'yes')
       OR v_kind <> ''
       OR v_cat LIKE '%shelf%'
       OR v_cat LIKE '%pantry%' THEN
      v_shelf := v_shelf + 1;
      CONTINUE;
    END IF;

    v_flag := lower(coalesce(
      v_item->>'is_hamper',
      v_item->'rawMealDetails'->>'is_hamper',
      ''
    ));
    IF v_flag IN ('true', 't', '1', 'yes')
       OR v_cat LIKE '%hamper%'
       OR v_cat LIKE '%festival%' THEN
      v_hamper := v_hamper + 1;
      CONTINUE;
    END IF;

    v_hot := v_hot + 1;
  END LOOP;

  IF v_hot > 0 THEN
    RETURN v_base;
  END IF;
  IF v_shelf > 0 AND v_hamper = 0 THEN
    RETURN 0;
  END IF;
  IF v_hamper > 0 THEN
    RETURN LEAST(v_base, 10);
  END IF;
  RETURN v_base;
END;
$$;

-- Catalog line total aligned with create-split-order/pricing.ts +
-- lib/utils/pricing_calculator.dart (discounted_price, offers, add-ons).
CREATE OR REPLACE FUNCTION public.catalog_line_total(p_item jsonb)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_meal_id uuid;
  v_qty int;
  v_list numeric;
  v_discounted numeric;
  v_offer text;
  v_disc numeric;
  v_cap numeric;
  v_unit numeric;
  v_gross numeric;
  v_net numeric;
  v_addon numeric := 0;
  v_addon_el jsonb;
  v_valid_from timestamptz;
  v_valid_until timestamptz;
  v_offer_live boolean := false;
  v_details jsonb;
BEGIN
  BEGIN
    v_meal_id := NULLIF(COALESCE(
      p_item->>'source_meal_id',
      p_item->>'meal_id',
      p_item->>'mealId',
      p_item->>'id'
    ), '')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;

  BEGIN
    v_qty := GREATEST(1, COALESCE(
      round(NULLIF(p_item->>'quantity', '')::numeric),
      NULLIF(p_item->>'qty', '')::numeric,
      1
    )::int);
  EXCEPTION WHEN OTHERS THEN
    v_qty := 1;
  END;
  v_qty := LEAST(v_qty, 99);

  v_details := COALESCE(p_item->'mealDetails', p_item->'rawMealDetails', p_item->'meal_details', '{}'::jsonb);

  IF v_meal_id IS NOT NULL THEN
    SELECT
      COALESCE(m.price, 0),
      COALESCE(m.discounted_price, 0),
      lower(coalesce(m.offer_type, '')),
      COALESCE(m.discount_value, 0),
      COALESCE(m.max_discount_cap, 0),
      m.offer_valid_from,
      m.offer_valid_until
    INTO v_list, v_discounted, v_offer, v_disc, v_cap, v_valid_from, v_valid_until
    FROM public.meals m
    WHERE m.id = v_meal_id;
  END IF;

  IF v_list IS NULL THEN
    -- Cart-JSON fallback so create-split-order can still use this RPC
    -- when a catalog row is missing.
    BEGIN
      v_list := COALESCE(
        NULLIF(p_item->>'discountedPrice', '')::numeric,
        NULLIF(p_item->>'discounted_price', '')::numeric,
        NULLIF(p_item->>'basePrice', '')::numeric,
        NULLIF(p_item->>'price', '')::numeric,
        NULLIF(p_item->>'base_price', '')::numeric,
        NULLIF(v_details->>'discounted_price', '')::numeric,
        NULLIF(v_details->>'price', '')::numeric,
        0
      );
    EXCEPTION WHEN OTHERS THEN
      v_list := 0;
    END;
    v_discounted := 0;
    v_offer := '';
    v_disc := 0;
    v_cap := 0;
  END IF;

  v_gross := ROUND(GREATEST(v_list, 0) * v_qty, 2);

  IF v_discounted > 0 AND (v_list <= 0 OR v_discounted < v_list) THEN
    v_net := ROUND(v_discounted * v_qty, 2);
  ELSE
    v_offer_live := v_offer IS NOT NULL AND v_offer <> '' AND v_offer <> 'none';
    IF v_valid_from IS NOT NULL AND now() < v_valid_from THEN
      v_offer_live := false;
    END IF;
    IF v_valid_until IS NOT NULL AND now() > v_valid_until THEN
      v_offer_live := false;
    END IF;

    v_net := v_gross;
    IF v_offer_live THEN
      IF v_offer LIKE '%bogo%' OR v_offer LIKE '%buy%get%' THEN
        v_net := ROUND(GREATEST(v_list, 0) * ((v_qty / 2) + (v_qty % 2)), 2);
      ELSIF v_offer LIKE '%percent%' OR v_offer LIKE '%flash%' THEN
        IF v_disc <= 0 AND v_offer LIKE '%flash%' THEN
          v_disc := 20;
        END IF;
        v_disc := LEAST(100, GREATEST(0, v_disc));
        v_unit := ROUND(GREATEST(v_list, 0) * (v_disc / 100.0) * v_qty, 2);
        IF v_cap > 0 THEN
          v_unit := LEAST(v_unit, v_cap);
        END IF;
        v_net := ROUND(GREATEST(0, v_gross - v_unit), 2);
      ELSIF v_offer LIKE '%flat%' THEN
        v_unit := LEAST(GREATEST(v_list, 0), GREATEST(0, v_disc));
        v_unit := ROUND(v_unit * v_qty, 2);
        IF v_cap > 0 THEN
          v_unit := LEAST(v_unit, v_cap);
        END IF;
        v_net := ROUND(GREATEST(0, v_gross - v_unit), 2);
      END IF;
    END IF;
  END IF;

  IF jsonb_typeof(COALESCE(p_item->'selectedAddOns', p_item->'selected_add_ons', p_item->'add_ons')) = 'array' THEN
    FOR v_addon_el IN
      SELECT * FROM jsonb_array_elements(
        COALESCE(p_item->'selectedAddOns', p_item->'selected_add_ons', p_item->'add_ons')
      )
    LOOP
      BEGIN
        v_addon := v_addon + LEAST(500, GREATEST(0, COALESCE(NULLIF(v_addon_el->>'price', '')::numeric, 0)));
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END LOOP;
  END IF;

  RETURN ROUND(GREATEST(v_net, 0) + (v_addon * v_qty), 2);
END;
$$;

-- ---------------------------------------------------------------------------
-- calculate_cart_total
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_cart_total(
  p_items jsonb,
  p_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_item jsonb;
  v_line numeric;
  v_food numeric := 0;
  v_packaging numeric := 20;
BEGIN
  v_packaging := public.packaging_fee_for_cart(
    COALESCE(p_user_id, auth.uid()),
    COALESCE(p_items, '[]'::jsonb)
  );

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RETURN jsonb_build_object(
      'items_total', 0,
      'item_total', 0,
      'subtotal', 0,
      'packaging_fee', v_packaging,
      'total', v_packaging
    );
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_line := COALESCE(public.catalog_line_total(v_item), 0);
    v_food := v_food + v_line;
  END LOOP;

  RETURN jsonb_build_object(
    'items_total', ROUND(v_food, 2),
    'item_total', ROUND(v_food, 2),
    'subtotal', ROUND(v_food, 2),
    'packaging_fee', v_packaging,
    'total', ROUND(v_food + v_packaging, 2)
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- place_customer_order
-- Callable by authenticated (Flutter post-Razorpay) and service_role.
-- ---------------------------------------------------------------------------
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
  v_line numeric;
  v_food_total numeric := 0;
  v_coins numeric := 0;
  v_total numeric;
  v_margin numeric := 0;
  v_order_type text;
  v_updated int;
  v_has_hold boolean := false;
  v_packaging numeric := 20;
  v_coins_ok boolean := true;
  v_kitchen_open boolean;
  v_title text;
  v_qty_total int := 0;
  v_customer_name text;
  v_first_meal uuid;
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
  ELSIF p_user_id IS NOT NULL AND p_user_id IS DISTINCT FROM v_customer_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'User mismatch');
  END IF;
  IF v_customer_id IS NULL AND p_customer_email IS NOT NULL THEN
    SELECT id INTO v_customer_id FROM users WHERE email = p_customer_email LIMIT 1;
  END IF;
  IF v_customer_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Customer not found');
  END IF;

  SELECT COALESCE(NULLIF(name, ''), NULLIF(full_name, ''), split_part(COALESCE(email, ''), '@', 1), 'Guest')
    INTO v_customer_name
  FROM users
  WHERE id = v_customer_id;

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

  v_packaging := public.packaging_fee_for_cart(v_customer_id, p_cart_items);

  v_order_type := COALESCE(
    p_cart_items->0->>'selectedServiceType',
    p_cart_items->0->>'selected_service_type',
    p_cart_items->0->>'service_type',
    p_cart_items->0->>'serviceType',
    'Delivery'
  );

  v_title := COALESCE(
    NULLIF(p_cart_items->0->>'title', ''),
    NULLIF(p_cart_items->0->>'name', ''),
    NULLIF(p_cart_items->0->'mealDetails'->>'title', ''),
    NULLIF(p_cart_items->0->'rawMealDetails'->>'title', ''),
    'Meal Order'
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
    v_qty_total := v_qty_total + v_qty;

    BEGIN
      v_meal_id := NULLIF(COALESCE(v_item->>'source_meal_id', v_item->>'meal_id', v_item->>'mealId', v_item->>'id'), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_meal_id := NULL;
    END;
    IF v_first_meal IS NULL THEN
      v_first_meal := v_meal_id;
    END IF;

    v_line := public.catalog_line_total(v_item);
    IF v_line IS NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'sold_out', 'error', 'A plate is no longer on the menu');
    END IF;

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

  IF COALESCE(p_apply_coins, false) AND v_coins_ok THEN
    SELECT COALESCE(hotpot_coins, 0) INTO v_coins FROM users WHERE id = v_customer_id;
    v_coins := LEAST(v_coins, v_food_total + COALESCE(p_delivery_fee, 0) + COALESCE(p_tip_amount, 0) + v_packaging);
  END IF;

  v_total := GREATEST(0, v_food_total + COALESCE(p_delivery_fee, 0) + COALESCE(p_tip_amount, 0) + v_packaging - v_coins);
  v_margin := ROUND(0.15 * GREATEST(0, v_food_total + v_packaging), 2);

  INSERT INTO orders (
    customer_id, user_id, chef_id, source_meal_id, items, cart_items,
    title, quantity, total_price, total_amount, price, status,
    order_type, service_type, payment_id, razorpay_order_id, razorpay_signature,
    delivery_address, special_instructions, idempotency_key, coins_applied,
    delivery_fee, packaging_fee, tip_amount, customer_phone, customer_name,
    customer_email, platform_margin, order_id, updated_at
  ) VALUES (
    v_customer_id, v_customer_id, v_chef_id, v_first_meal, p_cart_items, p_cart_items,
    v_title, GREATEST(v_qty_total, 1), v_total, v_total, v_total, 'Pending Chef Approval',
    v_order_type, v_order_type, p_payment_id, p_razorpay_order_id, p_razorpay_signature,
    p_delivery_address, p_instructions, p_idempotency_key, v_coins,
    COALESCE(p_delivery_fee, 0), v_packaging, COALESCE(p_tip_amount, 0),
    p_customer_phone, v_customer_name, p_customer_email, v_margin,
    p_payment_id, now()
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
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    BEGIN
      INSERT INTO transactions (user_id, amount, transaction_type, description)
      VALUES (v_customer_id, v_coins, 'debit', 'Coins applied at checkout');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  IF p_razorpay_order_id IS NOT NULL THEN
    UPDATE inventory_holds
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

-- ---------------------------------------------------------------------------
-- cancel_and_restock_order
-- ---------------------------------------------------------------------------
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
    v_items := to_jsonb(v_order.items);
    IF jsonb_typeof(v_items) = 'string' THEN
      v_items := (v_order.items)::text::jsonb;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      v_items := to_jsonb(v_order.cart_items);
      IF jsonb_typeof(v_items) = 'string' THEN
        v_items := (v_order.cart_items)::text::jsonb;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_items := '[]'::jsonb;
    END;
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
    BEGIN
      UPDATE wallets
      SET balance = COALESCE(balance, 0) + v_order.coins_applied,
          last_updated = now()
      WHERE user_id = v_order.customer_id;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    BEGIN
      INSERT INTO transactions (user_id, amount, transaction_type, description)
      VALUES (v_order.customer_id, v_order.coins_applied, 'refund', 'Coins restored after order cancel');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
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

-- ---------------------------------------------------------------------------
-- claim_daily_streak (IST calendar day, +15 coins)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_daily_streak(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_today date;
  v_streak int;
  v_last_date date;
  v_reward numeric := 15;
  v_updated int;
  v_delivered int;
BEGIN
  v_user_id := COALESCE(auth.uid(), p_user_id);
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Please sign in to claim.');
  END IF;
  IF auth.uid() IS NOT NULL AND p_user_id IS NOT NULL AND auth.uid() IS DISTINCT FROM p_user_id THEN
    RETURN jsonb_build_object('success', false, 'message', 'Please sign in to claim.');
  END IF;

  v_today := (timezone('Asia/Kolkata', now()))::date;

  SELECT current_streak, last_check_in_date
  INTO v_streak, v_last_date
  FROM public.user_gamification
  WHERE user_id = v_user_id;

  IF FOUND AND v_last_date = v_today THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Already claimed today. Coins stay in your wallet until you spend them at checkout.'
    );
  END IF;

  IF FOUND AND v_last_date = v_today - 1 THEN
    v_streak := COALESCE(v_streak, 0) + 1;
  ELSE
    v_streak := 1;
  END IF;

  INSERT INTO public.user_gamification (user_id, current_streak, last_check_in_date, updated_at)
  VALUES (v_user_id, v_streak, v_today, now())
  ON CONFLICT (user_id) DO UPDATE
  SET
    current_streak = EXCLUDED.current_streak,
    last_check_in_date = EXCLUDED.last_check_in_date,
    updated_at = now();

  UPDATE public.users
  SET hotpot_coins = COALESCE(hotpot_coins, 0) + v_reward
  WHERE id = v_user_id;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN jsonb_build_object('success', false, 'message', 'Could not add HotPot Coins. Try again.');
  END IF;

  BEGIN
    INSERT INTO public.transactions (user_id, amount, transaction_type, description)
    VALUES (v_user_id, v_reward, 'earning', 'Daily streak bonus');
  EXCEPTION
    WHEN undefined_table THEN NULL;
    WHEN OTHERS THEN NULL;
  END;

  SELECT COUNT(*)::int
  INTO v_delivered
  FROM public.orders
  WHERE customer_id = v_user_id
    AND (status ILIKE '%delivered%' OR status ILIKE '%completed%');

  UPDATE public.user_gamification
  SET
    total_orders_completed = v_delivered,
    loyalty_tier = CASE
      WHEN v_delivered >= 25 THEN 'Gold Foodie 🥇'
      WHEN v_delivered >= 10 THEN 'Silver Foodie 🥈'
      ELSE 'Bronze Foodie 🥉'
    END
  WHERE user_id = v_user_id;

  RETURN jsonb_build_object('success', true, 'streak', v_streak, 'reward', v_reward);
END;
$$;

REVOKE ALL ON FUNCTION public.release_checkout_inventory(text, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.expire_checkout_holds() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reserve_checkout_inventory(text, jsonb, uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.packaging_fee_for_loyalty(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.packaging_fee_for_cart(uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.catalog_line_total(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.calculate_cart_total(jsonb, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.place_customer_order(text, text, text, text, jsonb, boolean, text, uuid, numeric, numeric, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_and_restock_order(uuid, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_daily_streak(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.release_checkout_inventory(text, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.expire_checkout_holds() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_checkout_inventory(text, jsonb, uuid, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.packaging_fee_for_loyalty(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.packaging_fee_for_cart(uuid, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.catalog_line_total(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.calculate_cart_total(jsonb, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.place_customer_order(text, text, text, text, jsonb, boolean, text, uuid, numeric, numeric, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cancel_and_restock_order(uuid, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_daily_streak(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
