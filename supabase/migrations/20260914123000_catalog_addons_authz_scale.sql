-- Catalog add-on prices from meals.add_ons (not client JSON).
-- Drop JWT user_metadata.role from authorization.
-- Indexes for Home/orders. Rate-limit delivery PIN completes.

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
  v_offer text;
  v_disc numeric;
  v_unit numeric;
  v_billed int;
  v_meal_promo text;
  v_promo_type text;
  v_promo_val numeric;
  v_client_promo text;
  v_addon jsonb;
  v_addon_unit numeric := 0;
  v_addons jsonb;
  v_catalog_addons jsonb;
  v_cat jsonb;
  v_pick_id text;
  v_pick_title text;
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
  IF v_meal_id IS NULL THEN
    RETURN NULL;
  END IF;

  BEGIN
    v_qty := GREATEST(1, COALESCE(round(NULLIF(p_item->>'quantity', '')::numeric), NULLIF(p_item->>'qty', '')::numeric, 1)::int);
  EXCEPTION WHEN OTHERS THEN
    v_qty := 1;
  END;

  SELECT
    COALESCE(m.price, 0),
    lower(coalesce(to_jsonb(m)->>'offer_type', '')),
    COALESCE(NULLIF(to_jsonb(m)->>'discount_value', '')::numeric, 0),
    nullif(btrim(coalesce(to_jsonb(m)->>'promo_code', '')), ''),
    lower(coalesce(to_jsonb(m)->>'promo_discount_type', '')),
    COALESCE(NULLIF(to_jsonb(m)->>'promo_discount_value', '')::numeric, 0),
    COALESCE(m.add_ons, '[]'::jsonb)
  INTO v_list, v_offer, v_disc, v_meal_promo, v_promo_type, v_promo_val, v_catalog_addons
  FROM public.meals m
  WHERE m.id = v_meal_id;

  IF v_list IS NULL THEN
    RETURN NULL;
  END IF;

  v_unit := GREATEST(v_list, 0);
  v_billed := v_qty;

  IF v_offer LIKE '%bogo%' OR v_offer LIKE '%buy%get%' THEN
    v_billed := (v_qty + 1) / 2;
  ELSIF v_offer LIKE '%percent%' OR v_offer LIKE '%flash%' THEN
    IF v_disc <= 0 AND v_offer LIKE '%flash%' THEN
      v_disc := 20;
    END IF;
    IF v_disc > 0 THEN
      v_unit := ROUND(v_list * (1 - LEAST(v_disc, 90) / 100.0), 2);
    END IF;
  ELSIF v_offer LIKE '%flat%' THEN
    v_unit := GREATEST(0, ROUND(v_list - GREATEST(v_disc, 0), 2));
  END IF;

  v_client_promo := nullif(upper(btrim(coalesce(
    p_item->>'applied_promo_code',
    p_item->>'promo_code',
    p_item->>'promoCode',
    ''
  ))), '');
  IF v_meal_promo IS NOT NULL AND v_client_promo IS NOT NULL AND upper(v_meal_promo) = v_client_promo AND v_promo_val > 0 THEN
    IF v_promo_type LIKE '%percent%' THEN
      v_unit := ROUND(v_unit * (1 - LEAST(v_promo_val, 90) / 100.0), 2);
    ELSE
      v_unit := GREATEST(0, ROUND(v_unit - v_promo_val, 2));
    END IF;
  END IF;

  v_addons := COALESCE(p_item->'selectedAddOns', p_item->'selected_addons', p_item->'addOns', '[]'::jsonb);
  IF jsonb_typeof(v_addons) = 'array' AND jsonb_typeof(COALESCE(v_catalog_addons, '[]'::jsonb)) = 'array' THEN
    FOR v_addon IN SELECT * FROM jsonb_array_elements(v_addons)
    LOOP
      v_pick_id := lower(btrim(coalesce(v_addon->>'id', '')));
      v_pick_title := lower(btrim(coalesce(v_addon->>'title', v_addon->>'name', '')));
      FOR v_cat IN SELECT * FROM jsonb_array_elements(COALESCE(v_catalog_addons, '[]'::jsonb))
      LOOP
        IF (v_pick_id <> '' AND lower(btrim(coalesce(v_cat->>'id', ''))) = v_pick_id)
          OR (
            v_pick_title <> ''
            AND lower(btrim(coalesce(v_cat->>'title', v_cat->>'name', ''))) = v_pick_title
          )
        THEN
          BEGIN
            v_addon_unit := v_addon_unit + COALESCE(NULLIF(v_cat->>'price', '')::numeric, 0);
          EXCEPTION WHEN OTHERS THEN
            NULL;
          END;
          EXIT;
        END IF;
      END LOOP;
    END LOOP;
  END IF;

  RETURN ROUND(GREATEST(v_unit, 0) * v_billed + GREATEST(v_addon_unit, 0) * v_qty, 2);
END;
$$;

CREATE OR REPLACE FUNCTION public.is_platform_ops()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.platform_ops
    WHERE user_id = (select auth.uid())
  )
  OR lower(coalesce((select auth.jwt()) -> 'app_metadata' ->> 'role', '')) = 'ops';
$$;

CREATE OR REPLACE FUNCTION public.keep_users_signup_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_claimed text;
  v_locked text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_claimed := lower(btrim(coalesce(
      NEW.role::text,
      (select auth.jwt()) -> 'user_metadata' ->> 'role',
      'customer'
    )));
    IF v_claimed IN ('customer', 'diner') THEN
      v_locked := 'Customer';
    ELSIF v_claimed IN ('chef', 'cook') THEN
      v_locked := 'Chef';
    ELSIF v_claimed IN ('driver', 'delivery partner', 'delivery_partner') THEN
      v_locked := 'Driver';
    ELSE
      v_locked := 'Customer';
    END IF;
    NEW.role := v_locked;
    RETURN NEW;
  END IF;

  IF auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    NEW.role := OLD.role;
  END IF;
  RETURN NEW;
END;
$$;

DROP POLICY IF EXISTS orders_drivers_select ON public.orders;
CREATE POLICY orders_drivers_select ON public.orders
  FOR SELECT
  TO authenticated
  USING (
    (select auth.uid()) = driver_id
    OR (select auth.uid()) = delivery_partner_id
    OR (
      driver_id IS NULL
      AND delivery_partner_id IS NULL
      AND public.is_open_driver_job(status)
      AND public.is_partner_delivery(order_type)
      AND public.account_has_role(ARRAY['driver', 'delivery partner', 'delivery_partner'])
    )
  );

CREATE OR REPLACE FUNCTION public.complete_delivery_order(p_order_id uuid, p_otp text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  updated int;
  v_customer uuid;
  v_driver uuid;
  v_payout numeric;
  v_delivered int;
  v_row public.orders%ROWTYPE;
  v_entered text;
  v_expected text;
  v_is_assigned_driver boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  PERFORM public.assert_user_rate_limit('delivery_complete', 8, 15);

  SELECT * INTO v_row FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  v_is_assigned_driver :=
    (v_row.driver_id = auth.uid() OR v_row.delivery_partner_id = auth.uid())
    AND v_row.chef_id IS DISTINCT FROM auth.uid();

  IF v_is_assigned_driver THEN
    v_expected := regexp_replace(coalesce(v_row.delivery_otp, ''), '\D', '', 'g');
    v_entered := regexp_replace(coalesce(p_otp, ''), '\D', '', 'g');
    IF length(v_expected) < 4 OR v_expected IS DISTINCT FROM v_entered THEN
      RAISE EXCEPTION 'DELIVERY_PIN_REQUIRED';
    END IF;
  END IF;

  UPDATE public.orders
  SET
    status = 'Delivered',
    delivered_at = COALESCE(delivered_at, now()),
    driver_payout = CASE
      WHEN COALESCE(driver_payout, 0) > 0
        AND ABS(COALESCE(driver_payout, 0) - COALESCE(delivery_fee, 0)) >= 0.01
        THEN driver_payout
      ELSE COALESCE(NULLIF(delivery_fee, 0), 40) + COALESCE(tip_amount, 0)
    END,
    updated_at = now()
  WHERE id = p_order_id
    AND (
      driver_id = auth.uid()
      OR delivery_partner_id = auth.uid()
      OR chef_id = auth.uid()
    )
    AND status NOT ILIKE '%delivered%'
    AND status NOT ILIKE '%completed%'
    AND status NOT ILIKE '%cancel%'
  RETURNING customer_id, COALESCE(driver_id, delivery_partner_id), driver_payout
  INTO v_customer, v_driver, v_payout;

  GET DIAGNOSTICS updated = ROW_COUNT;
  IF updated = 0 THEN
    RETURN false;
  END IF;

  IF v_driver IS NOT NULL AND COALESCE(v_payout, 0) > 0 THEN
    INSERT INTO public.driver_profiles (user_id, wallet_balance, total_lifetime_earnings, updated_at)
    VALUES (v_driver, v_payout, v_payout, now())
    ON CONFLICT (user_id) DO UPDATE SET
      wallet_balance = COALESCE(public.driver_profiles.wallet_balance, 0) + EXCLUDED.wallet_balance,
      total_lifetime_earnings = COALESCE(public.driver_profiles.total_lifetime_earnings, 0) + EXCLUDED.total_lifetime_earnings,
      updated_at = now();
  END IF;

  IF v_customer IS NOT NULL THEN
    SELECT COUNT(*)::int
    INTO v_delivered
    FROM public.orders
    WHERE customer_id = v_customer
      AND (status ILIKE '%delivered%' OR status ILIKE '%completed%');

    UPDATE public.user_gamification
    SET
      total_orders_completed = v_delivered,
      loyalty_tier = CASE
        WHEN v_delivered >= 25 THEN 'Gold Foodie'
        WHEN v_delivered >= 10 THEN 'Silver Foodie'
        ELSE 'Bronze Foodie'
      END,
      updated_at = now()
    WHERE user_id = v_customer;
  END IF;

  RETURN true;
END;
$$;

CREATE INDEX IF NOT EXISTS meals_available_created_idx
  ON public.meals (created_at DESC)
  WHERE status = 'Available';

CREATE INDEX IF NOT EXISTS orders_chef_status_created_idx
  ON public.orders (chef_id, created_at DESC);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'reviews' AND column_name = 'chef_id'
  ) THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS reviews_chef_id_idx ON public.reviews (chef_id)';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.chef_rating_summaries(p_chef_ids uuid[])
RETURNS TABLE(chef_id uuid, average numeric, review_count integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT r.chef_id, round(avg(r.rating)::numeric, 2), count(*)::int
  FROM public.reviews r
  WHERE p_chef_ids IS NOT NULL
    AND cardinality(p_chef_ids) > 0
    AND cardinality(p_chef_ids) <= 80
    AND r.chef_id = ANY (p_chef_ids)
  GROUP BY r.chef_id;
$$;

REVOKE ALL ON FUNCTION public.chef_rating_summaries(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.chef_rating_summaries(uuid[]) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
