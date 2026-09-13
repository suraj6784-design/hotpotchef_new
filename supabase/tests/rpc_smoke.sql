-- Offline smoke checks for the five RPCs. Run after applying migrations
-- against a database that has auth.users (Supabase) or the stub below.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rpc_smoke.sql

CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users (
  id uuid PRIMARY KEY,
  email text
);

DO $$
DECLARE
  v_user uuid := '11111111-1111-1111-1111-111111111111';
  v_chef uuid := '22222222-2222-2222-2222-222222222222';
  v_meal uuid := '33333333-3333-3333-3333-333333333333';
  v_total jsonb;
  v_place jsonb;
  v_cancel jsonb;
  v_streak jsonb;
  v_match int;
  v_order uuid;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user, 'diner@example.com'),
    (v_chef, 'chef@example.com')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.users (id, email, name, role, hotpot_coins)
  VALUES
    (v_user, 'diner@example.com', 'Diner', 'Customer', 40),
    (v_chef, 'chef@example.com', 'Chef Kitchen', 'Chef', 0)
  ON CONFLICT (id) DO UPDATE SET hotpot_coins = EXCLUDED.hotpot_coins;

  INSERT INTO public.chef_profiles (user_id, is_open) VALUES (v_chef, true)
  ON CONFLICT (user_id) DO UPDATE SET is_open = true;

  INSERT INTO public.meals (id, chef_id, chef_name, title, price, quantity, status, category)
  VALUES (v_meal, v_chef, 'Chef Kitchen', 'Misal Pav', 120, 5, 'Available', 'Maharashtrian')
  ON CONFLICT (id) DO UPDATE SET quantity = 5, price = 120, status = 'Available';

  v_total := public.calculate_cart_total(
    jsonb_build_array(jsonb_build_object(
      'mealId', v_meal,
      'chef_id', v_chef,
      'quantity', 2,
      'title', 'Misal Pav'
    )),
    v_user
  );
  IF (v_total->>'subtotal')::numeric <> 240 THEN
    RAISE EXCEPTION 'calculate_cart_total subtotal expected 240, got %', v_total;
  END IF;
  IF (v_total->>'packaging_fee')::numeric <> 20 THEN
    RAISE EXCEPTION 'calculate_cart_total packaging expected 20, got %', v_total;
  END IF;

  v_place := public.place_customer_order(
    'diner@example.com',
    '9876543210',
    '1 Test St',
    'no onions',
    jsonb_build_array(jsonb_build_object(
      'mealId', v_meal,
      'chef_id', v_chef,
      'quantity', 2,
      'title', 'Misal Pav',
      'source_meal_id', v_meal
    )),
    true,
    'pay_smoke_1',
    v_user,
    10,
    30,
    'pay_smoke_1',
    'order_smoke_1',
    'sig_smoke'
  );
  IF v_place->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'place_customer_order failed: %', v_place;
  END IF;
  v_order := (v_place->>'order_id')::uuid;

  IF (SELECT quantity FROM public.meals WHERE id = v_meal) <> 3 THEN
    RAISE EXCEPTION 'stock not decremented';
  END IF;
  IF (SELECT hotpot_coins FROM public.users WHERE id = v_user) <> 0 THEN
    RAISE EXCEPTION 'coins not applied; balance=%', (SELECT hotpot_coins FROM public.users WHERE id = v_user);
  END IF;

  v_cancel := public.cancel_and_restock_order(v_order, 'Cancelled by kitchen', v_chef);
  IF v_cancel->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'cancel_and_restock_order failed: %', v_cancel;
  END IF;
  IF (SELECT quantity FROM public.meals WHERE id = v_meal) <> 5 THEN
    RAISE EXCEPTION 'stock not restocked';
  END IF;

  v_streak := public.claim_daily_streak(v_user);
  IF v_streak->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'claim_daily_streak failed: %', v_streak;
  END IF;
  IF (v_streak->>'reward')::numeric <> 15 THEN
    RAISE EXCEPTION 'streak reward expected 15, got %', v_streak;
  END IF;

  SELECT count(*) INTO v_match
  FROM public.match_meals(array_fill(0::float8, ARRAY[768])::vector(768), 0.0, 5);
  IF v_match <> 0 THEN
    RAISE EXCEPTION 'match_meals should be empty without embeddings, got %', v_match;
  END IF;

  -- camelCase Flutter cart keys still price from the meals catalog
  v_total := public.calculate_cart_total(
    jsonb_build_array(jsonb_build_object(
      'mealId', v_meal, 'chefId', v_chef, 'quantity', 1,
      'basePrice', 999, 'discountedPrice', 1
    )),
    v_user
  );
  IF (v_total->>'subtotal')::numeric <> 120 THEN
    RAISE EXCEPTION 'camelCase cart should use catalog 120, got %', v_total;
  END IF;

  v_place := public.place_customer_order(
    'diner@example.com', '9876543210', '1 Test St', '',
    jsonb_build_array(jsonb_build_object(
      'mealId', v_meal, 'chef_id', v_chef, 'quantity', 1,
      'title', 'Misal Pav', 'source_meal_id', v_meal
    )),
    false, 'pay_smoke_1', v_user, 0, 0, 'pay_smoke_1', 'order_smoke_1', 'sig'
  );
  IF v_place->>'idempotent' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'expected idempotent replay, got %', v_place;
  END IF;

  UPDATE chef_profiles SET is_open = false WHERE user_id = v_chef;
  v_place := public.place_customer_order(
    'diner@example.com', '9876543210', '1 Test St', '',
    jsonb_build_array(jsonb_build_object(
      'mealId', v_meal, 'chef_id', v_chef, 'quantity', 1,
      'title', 'Misal Pav', 'source_meal_id', v_meal
    )),
    false, 'pay_closed', v_user, 0, 0, 'pay_closed', NULL, NULL
  );
  IF v_place->>'code' IS DISTINCT FROM 'kitchen_closed' THEN
    RAISE EXCEPTION 'expected kitchen_closed, got %', v_place;
  END IF;
  UPDATE chef_profiles SET is_open = true WHERE user_id = v_chef;

  UPDATE meals SET quantity = 0 WHERE id = v_meal;
  v_place := public.place_customer_order(
    'diner@example.com', '9876543210', '1 Test St', '',
    jsonb_build_array(jsonb_build_object(
      'mealId', v_meal, 'chef_id', v_chef, 'quantity', 1,
      'title', 'Misal Pav', 'source_meal_id', v_meal
    )),
    false, 'pay_sold', v_user, 0, 0, 'pay_sold', NULL, NULL
  );
  IF v_place->>'code' IS DISTINCT FROM 'sold_out' THEN
    RAISE EXCEPTION 'expected sold_out, got %', v_place;
  END IF;

  v_streak := public.claim_daily_streak(v_user);
  IF v_streak->>'success' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'expected already-claimed streak, got %', v_streak;
  END IF;

  IF (
    SELECT count(*) FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relname IN ('orders', 'meals') AND NOT t.tgisinternal
      AND t.tgname IN ('on_order_push_webhook', 'on_meal_payout_webhook')
  ) <> 2 THEN
    RAISE EXCEPTION 'expected order + meal push triggers';
  END IF;

  RAISE NOTICE 'rpc_smoke ok place=% cancel=% streak=%', v_place, v_cancel, v_streak;
END $$;
