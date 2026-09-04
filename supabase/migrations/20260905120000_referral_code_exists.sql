-- Signup can check a friend's code without reading other users' rows.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS referral_code text,
  ADD COLUMN IF NOT EXISTS referred_by text,
  ADD COLUMN IF NOT EXISTS hotpot_coins numeric DEFAULT 0;

CREATE OR REPLACE FUNCTION public.referral_code_exists(p_code text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized text := upper(trim(coalesce(p_code, '')));
BEGIN
  IF normalized = '' THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1
    FROM public.users
    WHERE upper(trim(referral_code)) = normalized
  );
END;
$$;

REVOKE ALL ON FUNCTION public.referral_code_exists(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.referral_code_exists(text) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
