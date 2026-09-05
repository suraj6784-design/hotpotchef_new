-- Keep diner / chef / driver accounts from crossing hubs:
-- lock users.role after signup, require that role for claim/accept,
-- and stop JWT metadata.role from opening driver job lists.

CREATE OR REPLACE FUNCTION public.account_has_role(p_roles text[])
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid()
      AND lower(btrim(u.role::text)) = ANY (p_roles)
  );
$$;

REVOKE ALL ON FUNCTION public.account_has_role(text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.account_has_role(text[]) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.keep_users_signup_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    NEW.role := OLD.role;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_keep_signup_role ON public.users;
CREATE TRIGGER users_keep_signup_role
  BEFORE UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.keep_users_signup_role();

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
  IF auth.uid() IS NULL OR NOT public.account_has_role(ARRAY['chef', 'cook']) THEN
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

CREATE OR REPLACE FUNCTION public.accept_delivery_order(p_order_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  updated int;
BEGIN
  IF auth.uid() IS NULL OR NOT public.account_has_role(ARRAY['driver', 'delivery partner', 'delivery_partner']) THEN
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

REVOKE ALL ON FUNCTION public.accept_delivery_order(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_delivery_order(uuid) TO authenticated, service_role;

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
      AND public.account_has_role(ARRAY['driver', 'delivery partner', 'delivery_partner'])
    )
  );

DROP POLICY IF EXISTS driver_profiles_own ON public.driver_profiles;
CREATE POLICY driver_profiles_own ON public.driver_profiles
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (
    auth.uid() = user_id
    AND public.account_has_role(ARRAY['driver', 'delivery partner', 'delivery_partner'])
  );

DO $$
BEGIN
  IF to_regclass('public.customer_requests') IS NULL THEN
    RETURN;
  END IF;

  DROP POLICY IF EXISTS customer_requests_update ON public.customer_requests;
  CREATE POLICY customer_requests_update ON public.customer_requests
    FOR UPDATE
    TO authenticated
    USING (
      customer_id::text = auth.uid()::text
      OR accepted_chef_id::text = auth.uid()::text
      OR (
        lower(coalesce(status::text, '')) = 'open'
        AND public.account_has_role(ARRAY['chef', 'cook'])
      )
    )
    WITH CHECK (
      customer_id::text = auth.uid()::text
      OR accepted_chef_id::text = auth.uid()::text
    );
END $$;

NOTIFY pgrst, 'reload schema';
