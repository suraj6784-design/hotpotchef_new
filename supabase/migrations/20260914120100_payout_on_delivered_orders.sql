-- Chef payouts fire when an ORDER is delivered, not when a catalog meal
-- is paused / archived / retitled. Live `on_meal_payout_webhook` plus
-- `on_order_status_update` on public.meals caused 33× release-chef-payout
-- calls in 24h against 28 delivered orders all-time.
--
-- SAFE: trigger swap + additive orders payout columns. No table rebuilds.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS razorpay_transfer_id text,
  ADD COLUMN IF NOT EXISTS payout_status text,
  ADD COLUMN IF NOT EXISTS payout_released_at timestamptz;

-- Stop catalog churn from invoking payout / push edge functions.
DROP TRIGGER IF EXISTS on_meal_payout_webhook ON public.meals;
DROP TRIGGER IF EXISTS on_order_status_update ON public.meals;
DROP TRIGGER IF EXISTS on_meal_mutation ON public.meals;

-- Keep the old function as a no-op so any leftover trigger is harmless.
CREATE OR REPLACE FUNCTION public.handle_meal_payout_webhook()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Intentionally empty. Payouts are released from orders.status = delivered.
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_order_payout_webhook()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new text := lower(regexp_replace(COALESCE(NEW.status, ''), '[^a-z0-9]+', '', 'g'));
  v_old text := lower(regexp_replace(COALESCE(OLD.status, ''), '[^a-z0-9]+', '', 'g'));
BEGIN
  IF TG_OP <> 'UPDATE' THEN
    RETURN NEW;
  END IF;
  IF v_new NOT IN ('delivered', 'completed') THEN
    RETURN NEW;
  END IF;
  IF v_old IN ('delivered', 'completed') THEN
    RETURN NEW;
  END IF;

  PERFORM public.invoke_edge_push(
    public.edge_function_url('release-chef-payout'),
    jsonb_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'record', row_to_json(NEW),
      'old_record', to_jsonb(OLD)
    )
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_order_payout_webhook ON public.orders;
CREATE TRIGGER on_order_payout_webhook
AFTER UPDATE OF status ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.handle_order_payout_webhook();

NOTIFY pgrst, 'reload schema';
