-- Coin holds at checkout, SQL FSSAI + 4h prep gates, anon RPC revoke, paid-order lapse.

CREATE TABLE IF NOT EXISTS public.coin_holds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  razorpay_order_id text NOT NULL,
  amount numeric NOT NULL CHECK (amount >= 0),
  status text NOT NULL DEFAULT 'held'
    CHECK (status IN ('held', 'confirmed', 'released')),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS coin_holds_order_idx
  ON public.coin_holds (razorpay_order_id);

CREATE INDEX IF NOT EXISTS coin_holds_open_idx
  ON public.coin_holds (status, expires_at)
  WHERE status = 'held';

ALTER TABLE public.coin_holds ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS coin_holds_own ON public.coin_holds;
CREATE POLICY coin_holds_own ON public.coin_holds
  FOR SELECT
  USING (auth.uid() = user_id);

GRANT SELECT ON public.coin_holds TO authenticated;
GRANT ALL ON public.coin_holds TO service_role;

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

  FOR r IN
    SELECT * FROM coin_holds
    WHERE razorpay_order_id = p_razorpay_order_id
      AND status = 'held'
    FOR UPDATE
  LOOP
    IF v_actor IS NOT NULL AND NOT p_force AND r.user_id <> v_actor THEN
      RETURN jsonb_build_object('success', false, 'error', 'Not allowed to release this hold');
    END IF;

    UPDATE users
    SET hotpot_coins = COALESCE(hotpot_coins, 0) + r.amount
    WHERE id = r.user_id;

    BEGIN
      UPDATE wallets
      SET balance = COALESCE(balance, 0) + r.amount,
          last_updated = now()
      WHERE user_id = r.user_id;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    UPDATE coin_holds SET status = 'released' WHERE id = r.id;
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
    SELECT DISTINCT razorpay_order_id FROM (
      SELECT razorpay_order_id
      FROM inventory_holds
      WHERE status = 'held' AND expires_at < now()
      UNION
      SELECT razorpay_order_id
      FROM coin_holds
      WHERE status = 'held' AND expires_at < now()
    ) expired
  LOOP
    PERFORM public.release_checkout_inventory(oid, true);
    n := n + 1;
  END LOOP;
  RETURN jsonb_build_object('success', true, 'expired_orders', n);
END;
$$;

CREATE OR REPLACE FUNCTION public.reserve_checkout_coins(
  p_razorpay_order_id text,
  p_amount numeric,
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
  v_ttl int;
  v_amount numeric;
  v_balance numeric;
  v_oid text;
BEGIN
  PERFORM public.expire_checkout_holds();

  IF p_razorpay_order_id IS NULL OR btrim(p_razorpay_order_id) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Missing Razorpay order id');
  END IF;

  v_user := COALESCE(auth.uid(), p_user_id);
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Customer not found');
  END IF;

  v_amount := ROUND(GREATEST(0, COALESCE(p_amount, 0)), 2);
  v_ttl := GREATEST(5, LEAST(COALESCE(p_ttl_minutes, 15), 30));

  FOR v_oid IN
    SELECT DISTINCT razorpay_order_id FROM (
      SELECT razorpay_order_id FROM inventory_holds
      WHERE user_id = v_user AND status = 'held' AND razorpay_order_id <> p_razorpay_order_id
      UNION
      SELECT razorpay_order_id FROM coin_holds
      WHERE user_id = v_user AND status = 'held' AND razorpay_order_id <> p_razorpay_order_id
    ) other_holds
  LOOP
    PERFORM public.release_checkout_inventory(v_oid, true);
  END LOOP;

  IF v_amount <= 0 THEN
    RETURN jsonb_build_object('success', true, 'amount', 0);
  END IF;

  IF EXISTS (
    SELECT 1 FROM coin_holds
    WHERE razorpay_order_id = p_razorpay_order_id AND status = 'held'
  ) THEN
    RETURN jsonb_build_object('success', true, 'idempotent', true);
  END IF;

  SELECT COALESCE(hotpot_coins, 0) INTO v_balance
  FROM users
  WHERE id = v_user
  FOR UPDATE;

  IF v_balance IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Customer not found');
  END IF;
  IF v_balance + 0.001 < v_amount THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'insufficient_coins',
      'error', 'HotPot Coins changed. Pay the remainder online.'
    );
  END IF;

  UPDATE users
  SET hotpot_coins = GREATEST(0, COALESCE(hotpot_coins, 0) - v_amount)
  WHERE id = v_user;

  BEGIN
    UPDATE wallets
    SET balance = GREATEST(0, COALESCE(balance, 0) - v_amount),
        last_updated = now()
    WHERE user_id = v_user;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  INSERT INTO coin_holds (user_id, razorpay_order_id, amount, status, expires_at)
  VALUES (v_user, p_razorpay_order_id, v_amount, 'held', now() + make_interval(mins => v_ttl));

  RETURN jsonb_build_object('success', true, 'amount', v_amount);
END;
$$;

GRANT EXECUTE ON FUNCTION public.reserve_checkout_coins(text, numeric, uuid, integer) TO service_role;

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

  v_delivery := public.quote_checkout_delivery_fee(p_cart_items, v_drop_lat, v_drop_lng);
  v_packaging := public.packaging_fee_for_cart(v_customer_id, p_cart_items);

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
$$;

REVOKE ALL ON FUNCTION public.place_customer_order(
  text, text, text, text, jsonb, boolean, text, uuid, numeric, numeric, text, text, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.place_customer_order(
  text, text, text, text, jsonb, boolean, text, uuid, numeric, numeric, text, text, text
) TO service_role;

CREATE OR REPLACE FUNCTION public.chef_has_live_fssai(p_chef_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM users u
    WHERE u.id = p_chef_id
      AND regexp_replace(COALESCE(u.fssai_number, ''), '\D', '', 'g') ~ '^[12][0-9]{13}$'
      AND length(btrim(COALESCE(u.fssai_proof_url, ''))) > 0
      AND lower(COALESCE(u.fssai_verification_status, '')) = 'verified'
      AND (u.fssai_valid_until IS NULL OR u.fssai_valid_until >= CURRENT_DATE)
  );
$$;

CREATE OR REPLACE FUNCTION public.enforce_meal_fssai_for_available()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF lower(btrim(COALESCE(NEW.status, ''))) = 'available'
     AND NOT public.chef_has_live_fssai(NEW.chef_id) THEN
    RAISE EXCEPTION 'FSSAI must be verified before this plate can be Available';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS meals_enforce_fssai_available ON public.meals;
CREATE TRIGGER meals_enforce_fssai_available
  BEFORE INSERT OR UPDATE ON public.meals
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_meal_fssai_for_available();

CREATE OR REPLACE FUNCTION public.order_prep_slot_start(p_items text, p_created_at timestamptz)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_json jsonb;
  v_first jsonb := '{}'::jsonb;
  v_nested jsonb := '{}'::jsonb;
  v_slot text := '';
  v_date_raw text := '';
  v_slot_l text;
  v_hour int;
  v_min int := 0;
  v_ampm text;
  v_day date;
  v_ist date;
BEGIN
  BEGIN
    v_json := p_items::jsonb;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;

  IF jsonb_typeof(v_json) = 'array' AND jsonb_array_length(v_json) > 0 THEN
    v_first := COALESCE(v_json->0, '{}'::jsonb);
  ELSIF jsonb_typeof(v_json) = 'object' THEN
    v_first := v_json;
  END IF;

  v_nested := COALESCE(
    v_first->'rawMealDetails',
    v_first->'mealDetails',
    v_first->'meal_details',
    '{}'::jsonb
  );

  v_slot := COALESCE(
    NULLIF(v_first->>'exact_time', ''),
    NULLIF(v_first->>'timeSlot', ''),
    NULLIF(v_first->>'selected_slot', ''),
    NULLIF(v_first->>'delivery_slot', ''),
    NULLIF(v_first->>'time_slot', ''),
    NULLIF(v_nested->>'exact_time', ''),
    NULLIF(v_nested->>'timeSlot', ''),
    NULLIF(v_nested->>'time_slot', ''),
    ''
  );
  v_date_raw := COALESCE(
    NULLIF(v_first->>'selected_date', ''),
    NULLIF(v_first->>'selectedDate', ''),
    NULLIF(v_first->>'scheduled_date', ''),
    NULLIF(v_first->>'scheduledDate', ''),
    NULLIF(v_nested->>'selected_date', ''),
    NULLIF(v_nested->>'scheduled_date', ''),
    ''
  );

  v_slot_l := lower(btrim(v_slot));
  IF v_slot_l = '' OR v_slot_l IN ('asap', 'now', 'flexible')
     OR (v_slot_l LIKE '%flexible%')
     OR (v_slot_l LIKE '%asap%' AND v_slot_l !~ '\d{1,2}:\d{2}') THEN
    RETURN NULL;
  END IF;

  v_ist := (timezone('Asia/Kolkata', COALESCE(p_created_at, now())))::date;
  BEGIN
    IF v_date_raw ~ '^\d{4}-\d{2}-\d{2}' THEN
      v_day := substr(v_date_raw, 1, 10)::date;
    ELSIF v_date_raw ~ '^\d{2}/\d{2}/\d{4}' THEN
      v_day := to_date(substr(v_date_raw, 1, 10), 'DD/MM/YYYY');
    ELSE
      v_day := v_ist;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_day := v_ist;
  END;

  BEGIN
    IF v_slot ~* '(\d{1,2}):(\d{2})\s*(am|pm)' THEN
      v_hour := (regexp_match(v_slot, '(\d{1,2}):(\d{2})\s*(am|pm)', 'i'))[1]::int;
      v_min := (regexp_match(v_slot, '(\d{1,2}):(\d{2})\s*(am|pm)', 'i'))[2]::int;
      v_ampm := lower((regexp_match(v_slot, '(\d{1,2}):(\d{2})\s*(am|pm)', 'i'))[3]);
      IF v_ampm = 'pm' AND v_hour < 12 THEN v_hour := v_hour + 12; END IF;
      IF v_ampm = 'am' AND v_hour = 12 THEN v_hour := 0; END IF;
    ELSIF v_slot ~* '(\d{1,2})\s*(am|pm)' THEN
      v_hour := (regexp_match(v_slot, '(\d{1,2})\s*(am|pm)', 'i'))[1]::int;
      v_ampm := lower((regexp_match(v_slot, '(\d{1,2})\s*(am|pm)', 'i'))[2]);
      IF v_ampm = 'pm' AND v_hour < 12 THEN v_hour := v_hour + 12; END IF;
      IF v_ampm = 'am' AND v_hour = 12 THEN v_hour := 0; END IF;
    ELSIF v_slot ~ '(\d{1,2}):(\d{2})' THEN
      v_hour := (regexp_match(v_slot, '(\d{1,2}):(\d{2})'))[1]::int;
      v_min := (regexp_match(v_slot, '(\d{1,2}):(\d{2})'))[2]::int;
    ELSE
      RETURN NULL;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;

  IF v_hour IS NULL OR v_hour < 0 OR v_hour > 23 OR v_min < 0 OR v_min > 59 THEN
    RETURN NULL;
  END IF;

  RETURN (v_day + make_time(v_hour, v_min, 0)) AT TIME ZONE 'Asia/Kolkata';
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_chef_prep_window()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_slot timestamptz;
BEGIN
  IF lower(COALESCE(NEW.status, '')) LIKE '%prepar%'
     AND lower(COALESCE(OLD.status, '')) NOT LIKE '%prepar%' THEN
    v_slot := public.order_prep_slot_start(NEW.items::text, NEW.created_at);
    IF v_slot IS NOT NULL AND now() < (v_slot - interval '240 minutes') THEN
      RAISE EXCEPTION 'Too early to start preparing. Opens 4 hours before the requested time.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_enforce_chef_prep_window ON public.orders;
CREATE TRIGGER orders_enforce_chef_prep_window
  BEFORE UPDATE OF status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_chef_prep_window();

CREATE OR REPLACE FUNCTION public.lapse_unconfirmed_paid_orders()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_res jsonb;
  n int := 0;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Service only');
  END IF;

  FOR r IN
    SELECT id, payment_id
    FROM orders
    WHERE status = 'Pending Chef Approval'
      AND created_at < now() - interval '30 minutes'
      AND payment_id IS NOT NULL
      AND btrim(payment_id) <> ''
      AND lower(COALESCE(refund_status, '')) NOT IN ('processed', 'refunded', 'already_refunded')
    ORDER BY created_at
    LIMIT 40
  LOOP
    v_res := public.cancel_and_restock_order(r.id, 'Chef did not confirm in time', NULL);
    IF COALESCE(v_res->>'success', '') = 'true' THEN
      n := n + 1;
      IF r.payment_id NOT LIKE 'coins_%'
         AND lower(COALESCE(v_res->>'refund_status', '')) NOT IN ('processed', 'refunded', 'already_refunded') THEN
        UPDATE orders
        SET refund_status = 'pending',
            updated_at = now()
        WHERE id = r.id
          AND lower(COALESCE(refund_status, '')) NOT IN ('processed', 'refunded', 'already_refunded');
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'lapsed', n);
END;
$$;

REVOKE ALL ON FUNCTION public.lapse_unconfirmed_paid_orders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lapse_unconfirmed_paid_orders() TO service_role;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'cancel_and_restock_order',
        'complete_delivery_order',
        'reserve_checkout_inventory',
        'release_checkout_inventory',
        'expire_checkout_holds',
        'reserve_checkout_coins',
        'lapse_unconfirmed_paid_orders',
        'add_hotpot_coins',
        'credit_user_coins'
      )
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', r.sig);
    IF r.proname IN ('expire_checkout_holds', 'reserve_checkout_coins', 'lapse_unconfirmed_paid_orders', 'add_hotpot_coins', 'credit_user_coins') THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM authenticated', r.sig);
    END IF;
  END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public.release_checkout_inventory(text, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_checkout_inventory(text, jsonb, uuid, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.expire_checkout_holds() TO service_role;
GRANT EXECUTE ON FUNCTION public.cancel_and_restock_order(uuid, text, uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
