-- Atomic catering claim and driver accept (offline partners cannot take jobs).

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
    accepted_chef_name = COALESCE(NULLIF(btrim(p_chef_name), ''), accepted_chef_name)
  WHERE id = p_request_id
    AND accepted_chef_id IS NULL
    AND lower(COALESCE(status::text, '')) = 'open';

  GET DIAGNOSTICS updated = ROW_COUNT;
  RETURN updated > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_customer_request(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_customer_request(uuid, text) TO authenticated, service_role;

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
    status = 'Driver Assigned',
    updated_at = now()
  WHERE id = p_order_id
    AND driver_id IS NULL
    AND status ILIKE '%ready%';

  GET DIAGNOSTICS updated = ROW_COUNT;
  RETURN updated > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_delivery_order(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_delivery_order(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
