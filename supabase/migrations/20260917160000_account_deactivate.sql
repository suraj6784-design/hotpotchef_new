-- Diner self-service deactivate / activate. Ops suspension stays a separate status.

ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_account_status_check;
ALTER TABLE public.users
  ADD CONSTRAINT users_account_status_check
  CHECK (account_status IN ('active', 'suspended', 'deactivated'));

CREATE OR REPLACE FUNCTION public.set_own_account_status(p_active boolean)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
  v_next text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sign in required';
  END IF;

  SELECT lower(coalesce(account_status, 'active')) INTO v_status
  FROM public.users
  WHERE id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account not found';
  END IF;

  IF v_status = 'suspended' THEN
    RAISE EXCEPTION 'Account suspended — contact Support';
  END IF;

  v_next := CASE WHEN p_active THEN 'active' ELSE 'deactivated' END;

  UPDATE public.users
  SET account_status = v_next
  WHERE id = v_uid;

  RETURN v_next;
END;
$$;

REVOKE ALL ON FUNCTION public.set_own_account_status(boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_own_account_status(boolean) TO authenticated;
