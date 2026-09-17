-- Kitchens take orders when is_open. Weekly hour windows are no longer used.

CREATE OR REPLACE FUNCTION public.kitchen_accepting_orders(
  p_chef_id uuid,
  p_at timestamptz DEFAULT now()
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_open boolean;
BEGIN
  IF p_chef_id IS NULL THEN
    RETURN true;
  END IF;

  SELECT is_open
    INTO v_open
  FROM public.chef_profiles
  WHERE user_id = p_chef_id;

  IF NOT FOUND THEN
    RETURN true;
  END IF;
  RETURN v_open IS NOT FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.kitchen_accepting_orders(uuid, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.kitchen_accepting_orders(uuid, timestamptz) TO authenticated, service_role;

UPDATE public.chef_profiles
SET weekly_hours = '{}'::jsonb
WHERE weekly_hours IS DISTINCT FROM '{}'::jsonb;

COMMENT ON COLUMN public.chef_profiles.weekly_hours IS
  'Unused. Online/offline is chef_profiles.is_open. Kept so older clients do not error.';

NOTIFY pgrst, 'reload schema';
