-- Database triggers that POST order / meal status changes to Edge Functions.
--
-- Hosted Database Webhooks are NOT dumpable without the management API.
-- This in-database substitute matches:
--   supabase/functions/send-push-notification  (preferred FCM HTTP v1)
--   supabase/functions/push-notifier           (legacy FCM HTTP)
--   supabase/functions/release-chef-payout     (meals.status = Delivered)
--
-- Secrets (do NOT commit):
--   vault.create_secret('<service_role JWT>', 'edge_service_role_key');
--   vault.create_secret('<shared webhook secret>', 'edge_webhook_secret');  -- optional
--
-- If vault secrets are missing the trigger is a no-op (orders still save).
-- After `supabase db push`, also set Edge Function secrets:
--   FCM_SERVER_KEY / FIREBASE_SERVICE_ACCOUNT, SUPABASE_SERVICE_ROLE_KEY.
--
-- reconstructed from call sites — verify against hosted project before production
--
-- Project ref used in default URLs: tpcykyaumvqtwhuiiomg
-- Override via vault secrets edge_push_url / edge_payout_url if the project moves.

CREATE OR REPLACE FUNCTION public.invoke_edge_push(p_url text, p_body jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key text;
  v_shared text;
  v_headers jsonb;
BEGIN
  IF p_url IS NULL OR length(trim(p_url)) = 0 THEN
    RETURN;
  END IF;

  BEGIN
    SELECT decrypted_secret INTO v_key
    FROM vault.decrypted_secrets
    WHERE name = 'edge_service_role_key'
    LIMIT 1;
  EXCEPTION WHEN undefined_table OR undefined_object THEN
    v_key := NULL;
  END;

  BEGIN
    SELECT decrypted_secret INTO v_shared
    FROM vault.decrypted_secrets
    WHERE name = 'edge_webhook_secret'
    LIMIT 1;
  EXCEPTION WHEN undefined_table OR undefined_object THEN
    v_shared := NULL;
  END;

  IF v_key IS NULL OR length(trim(v_key)) < 20 THEN
    -- No live secret: skip HTTP so checkout / chef status updates never fail.
    RETURN;
  END IF;

  v_headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || trim(v_key)
  );
  IF v_shared IS NOT NULL AND length(trim(v_shared)) > 0 THEN
    v_headers := v_headers || jsonb_build_object('X-Webhook-Secret', trim(v_shared));
  END IF;

  BEGIN
    PERFORM net.http_post(
      url := p_url,
      headers := v_headers,
      body := COALESCE(p_body, '{}'::jsonb)
    );
  EXCEPTION WHEN undefined_function OR undefined_object THEN
    RAISE NOTICE 'pg_net.http_post unavailable; push webhook skipped';
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.invoke_edge_push(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.invoke_edge_push(text, jsonb) TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.edge_function_url(p_name text)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_override text;
  v_base text := 'https://tpcykyaumvqtwhuiiomg.supabase.co/functions/v1/';
BEGIN
  BEGIN
    SELECT decrypted_secret INTO v_override
    FROM vault.decrypted_secrets
    WHERE name = 'edge_' || replace(p_name, '-', '_') || '_url'
    LIMIT 1;
  EXCEPTION WHEN undefined_table OR undefined_object THEN
    v_override := NULL;
  END;
  IF v_override IS NOT NULL AND length(trim(v_override)) > 8 THEN
    RETURN trim(v_override);
  END IF;
  RETURN v_base || p_name;
END;
$$;

-- Preferred path: one FCM send per order status change via send-push-notification.
CREATE OR REPLACE FUNCTION public.handle_order_push_webhook()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;
  PERFORM public.invoke_edge_push(
    public.edge_function_url('send-push-notification'),
    jsonb_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'record', row_to_json(NEW),
      'old_record', CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END
    )
  );
  RETURN NEW;
END;
$$;

-- meals.status = Delivered + pending Razorpay transfer → release-chef-payout.
CREATE OR REPLACE FUNCTION public.handle_meal_payout_webhook()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.status IS NOT DISTINCT FROM NEW.status
     AND OLD.transfer_status IS NOT DISTINCT FROM NEW.transfer_status THEN
    RETURN NEW;
  END IF;
  PERFORM public.invoke_edge_push(
    public.edge_function_url('release-chef-payout'),
    jsonb_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'record', row_to_json(NEW),
      'old_record', CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END
    )
  );
  RETURN NEW;
END;
$$;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT t.tgname
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE n.nspname = 'public'
      AND c.relname = 'orders'
      AND NOT t.tgisinternal
      AND p.proname IN (
        'trigger_order_notification',
        'handle_order_status_change',
        'handle_order_push_webhook'
      )
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.orders', r.tgname);
  END LOOP;
END $$;

DROP TRIGGER IF EXISTS on_order_push_webhook ON public.orders;
CREATE TRIGGER on_order_push_webhook
AFTER INSERT OR UPDATE OF status ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.handle_order_push_webhook();

DROP TRIGGER IF EXISTS on_meal_payout_webhook ON public.meals;
CREATE TRIGGER on_meal_payout_webhook
AFTER UPDATE OF status, transfer_status ON public.meals
FOR EACH ROW
EXECUTE FUNCTION public.handle_meal_payout_webhook();

NOTIFY pgrst, 'reload schema';
