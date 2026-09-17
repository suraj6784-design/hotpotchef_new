-- Production hardening (not Razorpay live): RLS, revoke trigger/money RPCs, search_path, ops-cron.

CREATE TABLE IF NOT EXISTS public.user_favorites (
  user_id uuid NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  meal_id uuid NOT NULL REFERENCES public.meals (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, meal_id)
);

ALTER TABLE public.user_favorites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_favorites_own ON public.user_favorites;
CREATE POLICY user_favorites_own ON public.user_favorites
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

GRANT SELECT, INSERT, DELETE ON public.user_favorites TO authenticated;

DROP POLICY IF EXISTS favorites_own ON public.favorites;
CREATE POLICY favorites_own ON public.favorites
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

GRANT SELECT ON public.wallets TO authenticated;
DROP POLICY IF EXISTS wallets_own_select ON public.wallets;
CREATE POLICY wallets_own_select ON public.wallets
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS remote_ui_config_read_active ON public.remote_ui_config;
CREATE POLICY remote_ui_config_read_active ON public.remote_ui_config
  FOR SELECT TO anon, authenticated
  USING (is_active IS TRUE);

GRANT SELECT ON public.remote_ui_config TO anon, authenticated;

DROP POLICY IF EXISTS platform_settings_ops_read ON public.platform_settings;
CREATE POLICY platform_settings_ops_read ON public.platform_settings
  FOR SELECT TO authenticated
  USING (public.is_platform_ops());

DROP POLICY IF EXISTS api_rate_events_no_client ON public.api_rate_events;
CREATE POLICY api_rate_events_no_client ON public.api_rate_events
  FOR ALL TO authenticated
  USING (false)
  WITH CHECK (false);

DROP POLICY IF EXISTS email_lookup_attempts_no_client ON public.email_lookup_attempts;
CREATE POLICY email_lookup_attempts_no_client ON public.email_lookup_attempts
  FOR ALL TO authenticated
  USING (false)
  WITH CHECK (false);

REVOKE ALL ON TABLE public.spatial_ref_sys FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'handle_order_payout_webhook',
        'handle_meal_payout_webhook',
        'handle_new_user',
        'handle_new_user_role',
        'keep_users_signup_role',
        'clawback_referral_bonus_on_cancel',
        'grant_referral_bonus_after_order',
        'expire_lapsed_fssai_licences',
        'ops_escalate_overdue_tickets',
        'deduct_user_coins',
        'deduct_hotpot_coins',
        'credit_user_coins',
        'record_hotpot_coin_movement',
        'trigger_order_notification',
        'handle_order_status_change',
        'handle_order_push_webhook',
        'notify_ops_fssai_submission',
        'update_user_loyalty_tier',
        'grant_first_order_referral_bonus',
        'process_referral_reward'
      )
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
  END LOOP;
END $$;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname NOT LIKE 'st_%'
      AND p.proname NOT LIKE 'pg_%'
      AND (p.proconfig IS NULL OR NOT EXISTS (
        SELECT 1 FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) cfg
        WHERE cfg LIKE 'search_path=%'
      ))
  LOOP
    BEGIN
      EXECUTE format('ALTER FUNCTION %s SET search_path = public', r.sig);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM cron.job
    WHERE command ILIKE '%/functions/v1/ops-cron%'
      AND jobname <> 'ops-cron-edge'
  ) THEN
    PERFORM cron.unschedule('ops-cron-edge');
    RETURN;
  END IF;
  PERFORM cron.unschedule('ops-cron-edge');
  PERFORM cron.schedule(
    'ops-cron-edge',
    '*/10 * * * *',
    $cron$SELECT public.invoke_edge_push(
      'https://tpcykyaumvqtwhuiiomg.supabase.co/functions/v1/ops-cron',
      '{}'::jsonb
    );$cron$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ops-cron-edge schedule skipped';
END $$;

NOTIFY pgrst, 'reload schema';
