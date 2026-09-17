-- KYC ops can ping chefs/drivers in-app (and via FCM) to finish pending KYC.

CREATE TABLE IF NOT EXISTS public.user_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  title text NOT NULL,
  body text NOT NULL,
  kind text NOT NULL DEFAULT 'kyc_pending',
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users (id)
);

CREATE INDEX IF NOT EXISTS user_notifications_user_created_idx
  ON public.user_notifications (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS user_notifications_user_unread_idx
  ON public.user_notifications (user_id, created_at DESC)
  WHERE read_at IS NULL;

ALTER TABLE public.user_notifications ENABLE ROW LEVEL SECURITY;

GRANT SELECT, UPDATE ON public.user_notifications TO authenticated;
GRANT ALL ON public.user_notifications TO service_role;

DROP POLICY IF EXISTS user_notifications_select_own ON public.user_notifications;
CREATE POLICY user_notifications_select_own ON public.user_notifications
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS user_notifications_update_own ON public.user_notifications;
CREATE POLICY user_notifications_update_own ON public.user_notifications
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.user_notifications;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;

CREATE OR REPLACE FUNCTION public.ops_send_kyc_reminder(
  p_user_id uuid,
  p_missing text[] DEFAULT '{}'::text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_title text := 'Complete your KYC';
  v_body text;
  v_last timestamptz;
  v_id uuid;
  v_missing text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.ops_has_permission('kyc') THEN
    RAISE EXCEPTION 'KYC ops permission required';
  END IF;

  SELECT lower(role::text) INTO v_role
  FROM public.users
  WHERE id = p_user_id;

  IF v_role IS NULL OR v_role NOT IN ('chef', 'cook', 'driver') THEN
    RAISE EXCEPTION 'Reminders are only for chef or driver accounts';
  END IF;

  SELECT created_at INTO v_last
  FROM public.user_notifications
  WHERE user_id = p_user_id
    AND kind = 'kyc_pending'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_last IS NOT NULL AND v_last > now() - interval '4 hours' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'throttled', true,
      'retry_after_minutes', GREATEST(1, ceil(extract(epoch FROM (v_last + interval '4 hours' - now())) / 60.0)::int)
    );
  END IF;

  v_missing := nullif(array_to_string(
    ARRAY(SELECT trim(x) FROM unnest(coalesce(p_missing, '{}'::text[])) AS x WHERE trim(x) <> ''),
    ', '
  ), '');

  IF v_role = 'driver' THEN
    v_body := CASE
      WHEN v_missing IS NULL THEN
        'HotPotChef still needs your delivery-partner KYC. Open Profile and finish the missing details.'
      ELSE
        'Still needed: ' || v_missing || '. Open Profile to finish so we can keep you on jobs.'
    END;
  ELSE
    v_body := CASE
      WHEN v_missing IS NULL THEN
        'HotPotChef still needs your kitchen KYC. Open Profile and finish the missing details.'
      ELSE
        'Still needed: ' || v_missing || '. Open Profile to finish so we can keep your kitchen live.'
    END;
  END IF;

  INSERT INTO public.user_notifications (user_id, title, body, kind, data, created_by)
  VALUES (
    p_user_id,
    v_title,
    v_body,
    'kyc_pending',
    jsonb_build_object(
      'kind', 'kyc_pending',
      'role', v_role,
      'missing', to_jsonb(coalesce(p_missing, '{}'::text[]))
    ),
    auth.uid()
  )
  RETURNING id INTO v_id;

  PERFORM public.ops_audit_write(
    'kyc_reminder',
    'users',
    p_user_id::text,
    jsonb_build_object('notification_id', v_id, 'missing', coalesce(p_missing, '{}'::text[]))
  );

  RETURN jsonb_build_object('ok', true, 'id', v_id, 'title', v_title, 'body', v_body);
END;
$$;

REVOKE ALL ON FUNCTION public.ops_send_kyc_reminder(uuid, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ops_send_kyc_reminder(uuid, text[]) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
