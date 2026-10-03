-- Host changes to a Society/Office HotPOT land in each other member's Alerts inbox.
-- Guests cannot call this. The host is not notified about their own change.

CREATE OR REPLACE FUNCTION public.notify_group_room_change(
  p_room_code text,
  p_title text,
  p_body text,
  p_change text DEFAULT 'time'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text := upper(trim(coalesce(p_room_code, '')));
  v_title text := trim(coalesce(p_title, ''));
  v_body text := trim(coalesce(p_body, ''));
  v_change text := lower(trim(coalesce(p_change, 'time')));
  v_host uuid;
  v_member uuid;
  v_count integer := 0;
BEGIN
  IF auth.uid() IS NULL OR v_code = '' OR v_title = '' OR v_body = '' THEN
    RETURN 0;
  END IF;
  IF v_change NOT IN ('time', 'place', 'both') THEN
    v_change := 'time';
  END IF;

  SELECT host_id INTO v_host
  FROM public.shared_carts
  WHERE room_code = v_code;

  IF v_host IS NULL OR v_host <> auth.uid() THEN
    RETURN 0;
  END IF;

  FOR v_member IN
    SELECT DISTINCT uid
    FROM (
      SELECT m.user_id AS uid
      FROM public.shared_cart_members m
      WHERE m.room_code = v_code
      UNION
      SELECT (item->>'addedByUserId')::uuid AS uid
      FROM public.shared_carts sc
      CROSS JOIN LATERAL jsonb_array_elements(
        CASE
          WHEN jsonb_typeof(sc.items) = 'array' THEN sc.items
          ELSE '[]'::jsonb
        END
      ) AS item
      WHERE sc.room_code = v_code
        AND coalesce(item->>'addedByUserId', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ) people
    WHERE uid IS NOT NULL
      AND uid <> v_host
  LOOP
    INSERT INTO public.user_notifications (user_id, title, body, kind, data, created_by)
    VALUES (
      v_member,
      v_title,
      v_body,
      'group_room',
      jsonb_build_object(
        'kind', 'group_room',
        'room_code', v_code,
        'change', v_change
      ),
      auth.uid()
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_group_room_change(text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.notify_group_room_change(text, text, text, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
