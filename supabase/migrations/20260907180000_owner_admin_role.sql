-- Make suraj6784@gmail.com a dedicated Admin account (not Chef).
-- Strip chef_profiles and pause any meals listed under that user.

DO $$
DECLARE
  v_id uuid;
BEGIN
  SELECT id INTO v_id
  FROM auth.users
  WHERE lower(email) = lower(public.platform_owner_email())
  LIMIT 1;

  IF v_id IS NULL THEN
    RAISE NOTICE 'Owner email not found in auth.users; skip admin conversion';
    RETURN;
  END IF;

  -- Ensure owner ops seat
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
    -- Clear kitchen-facing compliance fields that imply an active chef listing
    fssai_number = NULL,
    fssai_proof_url = NULL,
    fssai_verification_status = 'unsubmitted',
    fssai_review_note = NULL,
    fssai_verified_at = NULL,
    fssai_reviewed_by = NULL
  WHERE id = v_id;

  UPDATE auth.users
  SET raw_user_meta_data =
    coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'Admin')
  WHERE id = v_id;

  DELETE FROM public.chef_profiles WHERE user_id = v_id;

  IF to_regclass('public.meals') IS NOT NULL THEN
    UPDATE public.meals
    SET status = 'Paused'
    WHERE chef_id = v_id;
  END IF;
END $$;

-- Keep Admin reserved: ops role changer cannot assign Admin.
CREATE OR REPLACE FUNCTION public.ops_set_user_role(p_user_id uuid, p_role text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text := initcap(lower(trim(coalesce(p_role, ''))));
  v_email text;
BEGIN
  IF NOT public.is_platform_owner() THEN
    RAISE EXCEPTION 'Platform owner only';
  END IF;

  IF v_role NOT IN ('Customer', 'Chef', 'Driver') THEN
    RAISE EXCEPTION 'Invalid role';
  END IF;

  SELECT lower(email) INTO v_email FROM auth.users WHERE id = p_user_id;
  IF v_email = lower(public.platform_owner_email()) THEN
    RAISE EXCEPTION 'Cannot change owner account role via ops';
  END IF;

  UPDATE public.users
  SET role = v_role
  WHERE id = p_user_id;

  UPDATE auth.users
  SET raw_user_meta_data =
    coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('role', v_role)
  WHERE id = p_user_id;

  RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ops_set_user_role(uuid, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
