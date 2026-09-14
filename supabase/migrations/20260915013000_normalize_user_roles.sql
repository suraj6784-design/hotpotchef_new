-- Canonical users.role: Customer | Chef | Driver | Admin.
-- Bare "Delivery" was locking three partners out of driver RPCs (account_has_role).

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
    IF v_claimed IN ('customer', 'diner', 'food lover', 'food_lover') THEN
      v_locked := 'Customer';
    ELSIF v_claimed IN ('chef', 'cook') THEN
      v_locked := 'Chef';
    ELSIF v_claimed IN (
      'driver',
      'delivery',
      'delivery partner',
      'delivery_partner',
      'deliverypartner'
    ) THEN
      v_locked := 'Driver';
    ELSE
      v_locked := 'Customer';
    END IF;
    NEW.role := v_locked;
    RETURN NEW;
  END IF;

  IF auth.role() = 'service_role'
     OR current_user IN ('postgres', 'supabase_admin') THEN
    RETURN NEW;
  END IF;
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    NEW.role := OLD.role;
  END IF;
  RETURN NEW;
END;
$$;

UPDATE public.users
SET role = CASE
  WHEN lower(btrim(coalesce(role::text, ''))) IN ('chef', 'cook') THEN 'Chef'
  WHEN lower(btrim(coalesce(role::text, ''))) IN (
    'driver',
    'delivery',
    'delivery partner',
    'delivery_partner',
    'deliverypartner'
  ) THEN 'Driver'
  WHEN lower(btrim(coalesce(role::text, ''))) IN (
    'admin',
    'ops',
    'platform',
    'platform admin',
    'platform_admin'
  ) THEN 'Admin'
  ELSE 'Customer'
END;

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
      AND public.account_has_role(ARRAY['driver', 'delivery', 'delivery partner', 'delivery_partner'])
    )
  );

NOTIFY pgrst, 'reload schema';
