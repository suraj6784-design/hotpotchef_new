-- Canonical Chef / Customer / Driver / Admin labels.
-- Live users.role mixed `Delivery Partner`, `Food Lover`, `Delivery`, `customer`.
-- JWT user_metadata and public.users used different strings; Flutter now maps
-- both through RouteAuthz.parseRole. This function is the SQL equivalent.

CREATE OR REPLACE FUNCTION public.normalize_app_role(p_role text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE regexp_replace(lower(btrim(COALESCE(p_role, ''))), '[_-]+', ' ', 'g')
    WHEN 'chef' THEN 'Chef'
    WHEN 'cook' THEN 'Chef'
    WHEN 'kitchen' THEN 'Chef'
    WHEN 'driver' THEN 'Driver'
    WHEN 'delivery' THEN 'Driver'
    WHEN 'delivery partner' THEN 'Driver'
    WHEN 'deliverypartner' THEN 'Driver'
    WHEN 'admin' THEN 'Admin'
    WHEN 'ops' THEN 'Admin'
    WHEN 'platform' THEN 'Admin'
    WHEN 'platform admin' THEN 'Admin'
    WHEN 'platformadmin' THEN 'Admin'
    WHEN 'customer' THEN 'Customer'
    WHEN 'food lover' THEN 'Customer'
    WHEN 'foodlover' THEN 'Customer'
    WHEN 'diner' THEN 'Customer'
    ELSE 'Customer'
  END;
$$;

REVOKE ALL ON FUNCTION public.normalize_app_role(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.normalize_app_role(text)
  TO anon, authenticated, service_role;

-- Tighten account_has_role so aliases match canonical Driver/Chef/Admin.
DO $$
BEGIN
  IF to_regprocedure('public.account_has_role(text[])') IS NOT NULL THEN
    EXECUTE $fn$
      CREATE OR REPLACE FUNCTION public.account_has_role(p_roles text[])
      RETURNS boolean
      LANGUAGE sql
      STABLE
      SECURITY DEFINER
      SET search_path = public
      AS $body$
        SELECT EXISTS (
          SELECT 1
          FROM public.users u
          WHERE u.id = auth.uid()
            AND public.normalize_app_role(u.role::text) = ANY (
              SELECT public.normalize_app_role(r) FROM unnest(p_roles) AS r
            )
        );
      $body$;
    $fn$;
  END IF;
END $$;

UPDATE public.users
SET role = public.normalize_app_role(role::text)
WHERE role IS DISTINCT FROM public.normalize_app_role(role::text);

NOTIFY pgrst, 'reload schema';
