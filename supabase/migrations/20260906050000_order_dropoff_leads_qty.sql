-- Persist checkout dropoff pins, and close remaining catering portions on claim.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_lat double precision;
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_lng double precision;

CREATE OR REPLACE FUNCTION public.set_order_dropoff(
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
  updated int;
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

  UPDATE public.orders
  SET
    delivery_lat = p_lat,
    delivery_lng = p_lng,
    updated_at = now()
  WHERE id = p_order_id
    AND customer_id = auth.uid();

  GET DIAGNOSTICS updated = ROW_COUNT;
  RETURN updated > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.set_order_dropoff(uuid, double precision, double precision) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_order_dropoff(uuid, double precision, double precision) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.claim_customer_request(p_request_id uuid, p_chef_name text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  updated int;
BEGIN
  IF to_regclass('public.customer_requests') IS NULL THEN
    RETURN false;
  END IF;
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  UPDATE public.customer_requests
  SET
    status = 'Accepted',
    accepted_chef_id = auth.uid(),
    accepted_chef_name = COALESCE(NULLIF(btrim(p_chef_name), ''), accepted_chef_name),
    remaining_quantity = 0
  WHERE id = p_request_id
    AND accepted_chef_id IS NULL
    AND lower(COALESCE(status::text, '')) = 'open';

  GET DIAGNOSTICS updated = ROW_COUNT;
  RETURN updated > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_customer_request(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_customer_request(uuid, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
