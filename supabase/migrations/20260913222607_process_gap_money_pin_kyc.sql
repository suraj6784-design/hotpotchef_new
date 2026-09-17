-- Process-gap contract: add-ons in catalog total, delivery PIN on insert,
-- driver complete requires PIN, partner jobs exclude chef-self/pickup/dine-in.

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
  v_promo_code text;
  v_meal_promo text;
  v_promo_type text;
  v_promo_val numeric;
  v_client_promo text;
  v_addon jsonb;
  v_addon_unit numeric := 0;
  v_addons jsonb;
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
    COALESCE(NULLIF(to_jsonb(m)->>'promo_discount_value', '')::numeric, 0)
  INTO v_list, v_offer, v_disc, v_meal_promo, v_promo_type, v_promo_val
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
  IF jsonb_typeof(v_addons) = 'array' THEN
    FOR v_addon IN SELECT * FROM jsonb_array_elements(v_addons)
    LOOP
      BEGIN
        v_addon_unit := v_addon_unit + COALESCE(NULLIF(v_addon->>'price', '')::numeric, 0);
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END LOOP;
  END IF;

  RETURN ROUND(GREATEST(v_unit, 0) * v_billed + GREATEST(v_addon_unit, 0) * v_qty, 2);
END;
$$;

CREATE OR REPLACE FUNCTION public.orders_stamp_delivery_otp()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.delivery_otp IS NULL OR btrim(NEW.delivery_otp) = '' THEN
    NEW.delivery_otp := lpad((floor(random() * 9000) + 1000)::int::text, 4, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_stamp_delivery_otp ON public.orders;
CREATE TRIGGER orders_stamp_delivery_otp
  BEFORE INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.orders_stamp_delivery_otp();

CREATE OR REPLACE FUNCTION public.is_partner_delivery(p_order_type text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    CASE
      WHEN p_order_type ILIKE '%self%'
        OR p_order_type ILIKE '%pickup%'
        OR p_order_type ILIKE '%pick up%'
        OR p_order_type ILIKE '%dine%'
        THEN false
      WHEN p_order_type ILIKE '%partner%'
        OR p_order_type ILIKE '%platform%'
        OR lower(btrim(coalesce(p_order_type, ''))) IN ('delivery', 'delivery_platform')
        THEN true
      WHEN p_order_type IS NULL OR btrim(p_order_type) = '' THEN true
      ELSE false
    END;
$$;

DROP FUNCTION IF EXISTS public.complete_delivery_order(uuid);

CREATE FUNCTION public.complete_delivery_order(p_order_id uuid, p_otp text DEFAULT NULL)
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

REVOKE ALL ON FUNCTION public.complete_delivery_order(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_delivery_order(uuid, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
