-- Point meal/order HTTP notify triggers at edge functions with Vault-backed
-- service-role Authorization. Do not store the key in git.

CREATE OR REPLACE FUNCTION public.invoke_edge_push(p_url text, p_body jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key text;
BEGIN
  SELECT decrypted_secret INTO v_key
  FROM vault.decrypted_secrets
  WHERE name = 'edge_service_role_key'
  LIMIT 1;
  IF v_key IS NULL OR length(trim(v_key)) < 20 THEN
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := p_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || trim(v_key)
    ),
    body := COALESCE(p_body, '{}'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.invoke_edge_push(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.invoke_edge_push(text, jsonb) TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.trigger_order_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.invoke_edge_push(
    'https://tpcykyaumvqtwhuiiomg.supabase.co/functions/v1/send-push-notification',
    jsonb_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'record', row_to_json(NEW)
    )
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_order_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;
  PERFORM public.invoke_edge_push(
    'https://tpcykyaumvqtwhuiiomg.supabase.co/functions/v1/send-push-notification',
    jsonb_build_object(
      'record', row_to_json(NEW),
      'old_record', row_to_json(OLD)
    )
  );
  RETURN NEW;
END;
$$;

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
    'https://tpcykyaumvqtwhuiiomg.supabase.co/functions/v1/push-notifier',
    jsonb_build_object(
      'record', row_to_json(NEW),
      'old_record', CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END
    )
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_order_push_webhook ON public.orders;
CREATE TRIGGER on_order_push_webhook
AFTER INSERT OR UPDATE OF status ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.handle_order_push_webhook();
