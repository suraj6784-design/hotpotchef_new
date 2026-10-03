-- Reveal the diner delivery PIN only after the partner reaches the dropoff.
-- The PIN is still stamped at insert. This timestamp is the reveal trigger.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS driver_arrived_at timestamptz;

COMMENT ON COLUMN public.orders.driver_arrived_at IS
  'Set when the assigned delivery partner is within 80m of delivery_lat/lng while out for delivery.';

CREATE OR REPLACE FUNCTION public.mark_driver_at_dropoff(
  p_order_id uuid,
  p_lat double precision,
  p_lng double precision
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.orders%ROWTYPE;
  v_km double precision;
BEGIN
  IF auth.uid() IS NULL OR p_order_id IS NULL THEN
    RETURN false;
  END IF;
  IF p_lat IS NULL OR p_lng IS NULL THEN
    RETURN false;
  END IF;
  IF abs(p_lat) < 0.0001 AND abs(p_lng) < 0.0001 THEN
    RETURN false;
  END IF;

  SELECT * INTO v_row FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_row.driver_id IS DISTINCT FROM auth.uid()
     AND v_row.delivery_partner_id IS DISTINCT FROM auth.uid() THEN
    RETURN false;
  END IF;

  IF v_row.driver_arrived_at IS NOT NULL THEN
    RETURN true;
  END IF;

  IF v_row.status ILIKE '%cancel%' OR v_row.status ILIKE '%reject%' THEN
    RETURN false;
  END IF;
  IF v_row.status ILIKE '%delivered%' OR v_row.status ILIKE '%completed%' THEN
    RETURN false;
  END IF;
  IF v_row.status NOT ILIKE '%out%' THEN
    RETURN false;
  END IF;

  IF v_row.delivery_lat IS NULL OR v_row.delivery_lng IS NULL THEN
    RETURN false;
  END IF;
  IF abs(v_row.delivery_lat) < 0.0001 AND abs(v_row.delivery_lng) < 0.0001 THEN
    RETURN false;
  END IF;

  v_km := 6371 * 2 * asin(sqrt(
    power(sin(radians(p_lat - v_row.delivery_lat) / 2), 2)
    + cos(radians(v_row.delivery_lat)) * cos(radians(p_lat))
      * power(sin(radians(p_lng - v_row.delivery_lng) / 2), 2)
  ));
  -- Same 80m gate as kDropoffArrivalRadiusMeters.
  IF v_km * 1000 > 80 THEN
    RETURN false;
  END IF;

  UPDATE public.orders
  SET
    driver_arrived_at = now(),
    updated_at = now()
  WHERE id = p_order_id
    AND driver_arrived_at IS NULL
    AND (
      driver_id = auth.uid()
      OR delivery_partner_id = auth.uid()
    );

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_driver_at_dropoff(uuid, double precision, double precision) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_driver_at_dropoff(uuid, double precision, double precision) TO authenticated, service_role;
