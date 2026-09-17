-- Drivers only saw status ILIKE '%ready%'. Partner jobs sit on
-- Pending / Confirmed / Preparing / orphaned Out for Delivery instead.

CREATE OR REPLACE FUNCTION public.is_open_driver_job(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    p_status IS NOT NULL
    AND p_status NOT ILIKE '%delivered%'
    AND p_status NOT ILIKE '%cancelled%'
    AND p_status NOT ILIKE '%rejected%'
    AND p_status NOT ILIKE '%completed%';
$$;

CREATE OR REPLACE FUNCTION public.is_partner_delivery(p_order_type text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    p_order_type IS NULL
    OR btrim(p_order_type) = ''
    OR p_order_type ILIKE '%partner%'
    OR p_order_type ILIKE '%platform%'
    OR lower(btrim(p_order_type)) IN ('delivery', 'delivery_platform');
$$;

CREATE OR REPLACE FUNCTION public.accept_delivery_order(p_order_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  updated int;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.driver_profiles
    WHERE user_id = auth.uid()
      AND is_available = false
  ) THEN
    RETURN false;
  END IF;

  UPDATE public.orders
  SET
    driver_id = auth.uid(),
    delivery_partner_id = auth.uid(),
    status = CASE
      WHEN status ILIKE '%out%' THEN status
      ELSE 'Driver Assigned'
    END,
    updated_at = now()
  WHERE id = p_order_id
    AND driver_id IS NULL
    AND delivery_partner_id IS NULL
    AND public.is_open_driver_job(status)
    AND public.is_partner_delivery(order_type);

  GET DIAGNOSTICS updated = ROW_COUNT;
  RETURN updated > 0;
END;
$$;

DROP POLICY IF EXISTS orders_drivers_select ON public.orders;
CREATE POLICY orders_drivers_select ON public.orders
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = driver_id
    OR auth.uid() = delivery_partner_id
    OR (
      driver_id IS NULL
      AND delivery_partner_id IS NULL
      AND public.is_open_driver_job(status)
      AND public.is_partner_delivery(order_type)
      AND (
        EXISTS (
          SELECT 1 FROM public.driver_profiles dp WHERE dp.user_id = auth.uid()
        )
        OR lower(coalesce(auth.jwt() -> 'user_metadata' ->> 'role', ''))
          IN ('driver', 'delivery partner', 'delivery_partner')
        OR EXISTS (
          SELECT 1
          FROM public.users u
          WHERE u.id = auth.uid()
            AND lower(u.role) IN ('driver', 'delivery partner', 'delivery_partner')
        )
      )
    )
  );

NOTIFY pgrst, 'reload schema';
