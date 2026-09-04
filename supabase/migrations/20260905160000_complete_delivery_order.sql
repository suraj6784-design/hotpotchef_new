-- Mark Delivered wrote orders.delivered_at, which the live table may not have.
-- Give drivers a SECURITY DEFINER complete path and persist the timestamp.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivered_at timestamptz;

CREATE OR REPLACE FUNCTION public.complete_delivery_order(p_order_id uuid)
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

  UPDATE public.orders
  SET
    status = 'Delivered',
    delivered_at = COALESCE(delivered_at, now()),
    updated_at = now()
  WHERE id = p_order_id
    AND (
      driver_id = auth.uid()
      OR delivery_partner_id = auth.uid()
      OR chef_id = auth.uid()
    )
    AND status NOT ILIKE '%delivered%'
    AND status NOT ILIKE '%completed%'
    AND status NOT ILIKE '%cancel%';

  GET DIAGNOSTICS updated = ROW_COUNT;
  RETURN updated > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_delivery_order(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_delivery_order(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
