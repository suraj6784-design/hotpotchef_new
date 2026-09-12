-- One FCM send per order status change. Extra order-push triggers stacked
-- "New order" / "Order confirmed" in the phone tray.

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
    'https://tpcykyaumvqtwhuiiomg.supabase.co/functions/v1/send-push-notification',
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
