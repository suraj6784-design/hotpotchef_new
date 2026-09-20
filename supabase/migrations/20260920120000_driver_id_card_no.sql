-- Unique public Digital ID number for delivery partners.
-- Assigned when the users row is created as Driver, or when role becomes Driver.

CREATE SEQUENCE IF NOT EXISTS public.driver_id_card_seq
  AS bigint
  START WITH 100001
  INCREMENT BY 1
  MINVALUE 100001
  NO MAXVALUE
  CACHE 1;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS driver_id_no text;

CREATE UNIQUE INDEX IF NOT EXISTS users_driver_id_no_uidx
  ON public.users (driver_id_no)
  WHERE driver_id_no IS NOT NULL AND length(btrim(driver_id_no)) > 0;

CREATE OR REPLACE FUNCTION public.next_driver_id_no()
RETURNS text
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN 'HPC-D' || lpad(nextval('public.driver_id_card_seq')::text, 6, '0');
END;
$$;

CREATE OR REPLACE FUNCTION public.users_assign_driver_id_no()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.driver_id_no IS NOT NULL
     AND btrim(OLD.driver_id_no) <> '' THEN
    NEW.driver_id_no := OLD.driver_id_no;
    RETURN NEW;
  END IF;

  IF lower(coalesce(NEW.role, '')) IN ('driver', 'delivery', 'delivery partner', 'delivery_partner') THEN
    IF NEW.driver_id_no IS NULL OR btrim(NEW.driver_id_no) = '' THEN
      NEW.driver_id_no := public.next_driver_id_no();
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_assign_driver_id_no_trg ON public.users;
CREATE TRIGGER users_assign_driver_id_no_trg
  BEFORE INSERT OR UPDATE OF role, driver_id_no
  ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.users_assign_driver_id_no();

CREATE OR REPLACE FUNCTION public.ensure_own_driver_id_no()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_no text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sign in required';
  END IF;

  SELECT role, driver_id_no INTO v_role, v_no
  FROM public.users
  WHERE id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account not found';
  END IF;

  IF lower(coalesce(v_role, '')) NOT IN ('driver', 'delivery', 'delivery partner', 'delivery_partner') THEN
    RETURN NULL;
  END IF;

  IF v_no IS NULL OR btrim(v_no) = '' THEN
    v_no := public.next_driver_id_no();
    UPDATE public.users SET driver_id_no = v_no WHERE id = v_uid;
  END IF;

  RETURN v_no;
END;
$$;

REVOKE ALL ON FUNCTION public.next_driver_id_no() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ensure_own_driver_id_no() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_own_driver_id_no() TO authenticated;

UPDATE public.users
SET driver_id_no = public.next_driver_id_no()
WHERE driver_id_no IS NULL
  AND lower(coalesce(role, '')) IN ('driver', 'delivery', 'delivery partner', 'delivery_partner');

COMMENT ON COLUMN public.users.driver_id_no IS 'Public Digital ID number (HPC-D######). Assigned at Driver account creation.';
