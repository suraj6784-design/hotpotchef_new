-- Ops helper to inspect / clear stuck inventory_holds.
--
-- Audit 2026-09-14: 37 rows status=confirmed, all already past expires_at.
-- `confirmed` means place_customer_order finished and stock was consumed.
-- Blind restock would double inventory on real orders.
--
-- This migration does NOT mutate holds. It installs a dry-run-default RPC.
--
-- Usage (service_role / SQL editor):
--   SELECT public.ops_release_stale_confirmed_holds(true);   -- inspect
--   SELECT public.ops_release_stale_confirmed_holds(false);  -- apply
--
-- Apply rules:
--   * Only status = 'confirmed' AND expires_at < now()
--   * If an orders row exists with the same razorpay_order_id and is not
--     cancelled → mark hold released WITHOUT restocking (order already owns stock)
--   * If no matching order (or the order is cancelled) → restock quantity
--     and mark released (orphan checkout)
--   * Never touches status = 'held' (expire_checkout_holds already covers those)

CREATE OR REPLACE FUNCTION public.ops_release_stale_confirmed_holds(
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_has_active_order boolean;
  v_restock int := 0;
  v_mark_only int := 0;
  v_ids uuid[] := ARRAY[]::uuid[];
BEGIN
  FOR r IN
    SELECT h.*
    FROM public.inventory_holds h
    WHERE h.status = 'confirmed'
      AND h.expires_at < now()
    FOR UPDATE SKIP LOCKED
  LOOP
    SELECT EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.razorpay_order_id = r.razorpay_order_id
        AND lower(regexp_replace(COALESCE(o.status, ''), '[^a-z0-9]+', '', 'g'))
            NOT IN ('cancelled', 'canceled', 'rejected')
    ) INTO v_has_active_order;

    v_ids := array_append(v_ids, r.id);

    IF v_has_active_order THEN
      v_mark_only := v_mark_only + 1;
      IF NOT p_dry_run THEN
        UPDATE public.inventory_holds
        SET status = 'released'
        WHERE id = r.id AND status = 'confirmed';
      END IF;
    ELSE
      v_restock := v_restock + 1;
      IF NOT p_dry_run THEN
        UPDATE public.meals
        SET quantity = COALESCE(quantity, 0) + r.quantity,
            status = CASE
              WHEN lower(COALESCE(status, '')) IN ('sold out', 'sold_out') THEN 'Available'
              ELSE status
            END
        WHERE id = r.meal_id;

        UPDATE public.inventory_holds
        SET status = 'released'
        WHERE id = r.id AND status = 'confirmed';
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'candidates', COALESCE(array_length(v_ids, 1), 0),
    'would_mark_released_no_restock', v_mark_only,
    'would_restock_orphans', v_restock,
    'hold_ids', to_jsonb(v_ids),
    'note', 'confirmed holds with a live order are marked released only; orphans restock. held rows are ignored.'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ops_release_stale_confirmed_holds(boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_release_stale_confirmed_holds(boolean) TO postgres, service_role;

COMMENT ON FUNCTION public.ops_release_stale_confirmed_holds(boolean) IS
  'Inspect or clear expired confirmed inventory_holds. Default dry_run=true. service_role only.';

NOTIFY pgrst, 'reload schema';
