-- Guest Home FSSAI chips must not SELECT public.users (anon has no table grant,
-- and a full GRANT would leak diner/driver PII). Chefs only, public fields.

CREATE OR REPLACE FUNCTION public.chef_fssai_public(p_ids uuid[])
RETURNS TABLE (
  id uuid,
  fssai_verification_status text,
  fssai_valid_until date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT u.id, u.fssai_verification_status, u.fssai_valid_until
  FROM public.users u
  WHERE p_ids IS NOT NULL
    AND u.id = ANY (p_ids)
    AND lower(btrim(u.role::text)) IN ('chef', 'cook');
$$;

REVOKE ALL ON FUNCTION public.chef_fssai_public(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.chef_fssai_public(uuid[]) TO anon, authenticated;

COMMENT ON FUNCTION public.chef_fssai_public(uuid[]) IS
  'Guest/authenticated FSSAI chip fields for chef ids only. No phone, email, or documents.';
