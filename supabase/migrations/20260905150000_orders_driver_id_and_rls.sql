-- Live orders store the partner on delivery_partner_id. The app and
-- accept_delivery_order use driver_id, so selects failed with PGRST204
-- and drivers had no SELECT policy at all.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS driver_id uuid;

UPDATE public.orders
SET driver_id = delivery_partner_id
WHERE driver_id IS NULL
  AND delivery_partner_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS orders_driver_id_idx
  ON public.orders (driver_id);

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
    status = 'Driver Assigned',
    updated_at = now()
  WHERE id = p_order_id
    AND driver_id IS NULL
    AND delivery_partner_id IS NULL
    AND status ILIKE '%ready%';

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
      AND status ILIKE '%ready%'
      AND (
        lower(coalesce(auth.jwt() -> 'user_metadata' ->> 'role', ''))
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
