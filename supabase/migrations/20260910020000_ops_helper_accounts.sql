-- Owner-created helper logins (username/password) instead of invite codes.

CREATE OR REPLACE FUNCTION public.ops_list_helpers()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_platform_owner() THEN
    RAISE EXCEPTION 'Platform owner only';
  END IF;

  RETURN coalesce((
    SELECT jsonb_agg(to_jsonb(q) ORDER BY q.created_at DESC)
    FROM (
      SELECT
        po.user_id,
        po.seat_role,
        po.permissions,
        po.note,
        po.revoked_at,
        po.created_at,
        u.email,
        u.name,
        u.full_name,
        u.account_status
      FROM public.platform_ops po
      LEFT JOIN public.users u ON u.id = po.user_id
      WHERE po.seat_role = 'helper'
      LIMIT 200
    ) q
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.ops_list_helpers() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ops_list_helpers() TO authenticated, service_role;
