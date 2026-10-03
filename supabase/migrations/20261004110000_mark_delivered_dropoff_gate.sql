-- Mark Delivered uses the same 80m dropoff gate as the diner PIN.
-- Assigned partners must send a live fix within kDropoffArrivalRadiusMeters.
-- Chef-self, pickup, and dine-in completion (chef_id = auth.uid()) is unchanged.

DROP FUNCTION IF EXISTS public.complete_delivery_order(uuid, text, text);
DROP FUNCTION IF EXISTS public.complete_delivery_order(uuid, text);
DROP FUNCTION IF EXISTS public.complete_delivery_order(uuid);

CREATE OR REPLACE FUNCTION public.complete_delivery_order(
  p_order_id uuid,
  p_otp text DEFAULT NULL,
  p_pod_url text DEFAULT NULL,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL
)
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
  v_pod text;
  v_km double precision;
  v_at_dropoff boolean := false;
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
    IF p_lat IS NULL OR p_lng IS NULL THEN
      RAISE EXCEPTION 'DROPOFF_TOO_FAR';
    END IF;
    IF abs(p_lat) < 0.0001 AND abs(p_lng) < 0.0001 THEN
      RAISE EXCEPTION 'DROPOFF_TOO_FAR';
    END IF;
    IF v_row.delivery_lat IS NULL OR v_row.delivery_lng IS NULL THEN
      RAISE EXCEPTION 'DROPOFF_TOO_FAR';
    END IF;
    IF abs(v_row.delivery_lat) < 0.0001 AND abs(v_row.delivery_lng) < 0.0001 THEN
      RAISE EXCEPTION 'DROPOFF_TOO_FAR';
    END IF;

    -- Same haversine and 80m gate as mark_driver_at_dropoff / kDropoffArrivalRadiusMeters.
    v_km := 6371 * 2 * asin(sqrt(
      power(sin(radians(p_lat - v_row.delivery_lat) / 2), 2)
      + cos(radians(v_row.delivery_lat)) * cos(radians(p_lat))
        * power(sin(radians(p_lng - v_row.delivery_lng) / 2), 2)
    ));
    IF v_km * 1000 > 80 THEN
      RAISE EXCEPTION 'DROPOFF_TOO_FAR';
    END IF;
    v_at_dropoff := true;

    v_expected := regexp_replace(coalesce(v_row.delivery_otp, ''), '\D', '', 'g');
    v_entered := regexp_replace(coalesce(p_otp, ''), '\D', '', 'g');
    IF length(v_expected) < 4 OR v_expected IS DISTINCT FROM v_entered THEN
      RAISE EXCEPTION 'DELIVERY_PIN_REQUIRED';
    END IF;
    v_pod := nullif(btrim(coalesce(p_pod_url, v_row.pod_photo_url, '')), '');
    IF v_pod IS NULL OR v_pod NOT LIKE 'http%' THEN
      RAISE EXCEPTION 'POD_PHOTO_REQUIRED';
    END IF;
  ELSE
    v_pod := nullif(btrim(coalesce(p_pod_url, v_row.pod_photo_url, '')), '');
  END IF;

  UPDATE public.orders
  SET
    status = 'Delivered',
    delivered_at = COALESCE(delivered_at, now()),
    driver_arrived_at = CASE
      WHEN v_at_dropoff THEN COALESCE(driver_arrived_at, now())
      ELSE driver_arrived_at
    END,
    pod_photo_url = COALESCE(v_pod, pod_photo_url),
    pod_captured_at = CASE
      WHEN v_pod IS NOT NULL THEN COALESCE(pod_captured_at, now())
      ELSE pod_captured_at
    END,
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

REVOKE ALL ON FUNCTION public.complete_delivery_order(uuid, text, text, double precision, double precision) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_delivery_order(uuid, text, text, double precision, double precision) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
