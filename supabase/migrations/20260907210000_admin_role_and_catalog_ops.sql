-- Role lock was blocking Admin conversion and ops_set_user_role.
-- Allow owner/service/postgres updates, then convert the owner account.

CREATE OR REPLACE FUNCTION public.keep_users_signup_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.role IS NOT DISTINCT FROM OLD.role THEN
    RETURN NEW;
  END IF;

  IF auth.role() IN ('service_role')
     OR current_user IN ('postgres', 'supabase_admin')
     OR public.is_platform_owner()
     OR (
       lower(NEW.role::text) = 'admin'
       AND EXISTS (
         SELECT 1
         FROM auth.users au
         WHERE au.id = NEW.id
           AND lower(au.email) = lower(public.platform_owner_email())
       )
     )
  THEN
    RETURN NEW;
  END IF;

  NEW.role := OLD.role;
  RETURN NEW;
END;
$$;

DO $$
DECLARE
  v_id uuid;
BEGIN
  SELECT id INTO v_id
  FROM auth.users
  WHERE lower(email) = lower(public.platform_owner_email())
  LIMIT 1;

  IF v_id IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.platform_ops (user_id, note, seat_role, permissions, revoked_at)
  VALUES (v_id, 'exclusive HotPotChef platform owner', 'owner', '{}'::text[], NULL)
  ON CONFLICT (user_id) DO UPDATE
  SET
    seat_role = 'owner',
    permissions = '{}'::text[],
    note = 'exclusive HotPotChef platform owner',
    revoked_at = NULL;

  UPDATE public.users
  SET
    role = 'Admin',
    fssai_number = NULL,
    fssai_proof_url = NULL,
    fssai_verification_status = 'unsubmitted'
  WHERE id = v_id;

  UPDATE auth.users
  SET raw_user_meta_data =
    coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'Admin')
  WHERE id = v_id;

  DELETE FROM public.chef_profiles WHERE user_id = v_id;

  IF to_regclass('public.meals') IS NOT NULL THEN
    UPDATE public.meals
    SET status = 'Paused'
    WHERE chef_id = v_id
      AND lower(coalesce(status, '')) = 'available';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.ops_set_meal_status(p_meal_id uuid, p_status text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text := initcap(lower(trim(coalesce(p_status, ''))));
BEGIN
  IF NOT public.is_platform_owner() THEN
    RAISE EXCEPTION 'Platform owner only';
  END IF;
  IF v_status NOT IN ('Available', 'Paused') THEN
    RAISE EXCEPTION 'status must be Available or Paused';
  END IF;
  UPDATE public.meals
  SET status = v_status
  WHERE id = p_meal_id;
  RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ops_set_meal_status(uuid, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
