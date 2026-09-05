-- "Saved from waste" = pre-order cook-to-demand (not leftover flash rescue).
-- Counts slotted (non-ASAP) plates ordered this IST week + meals still open to pre-order.

CREATE OR REPLACE FUNCTION public.get_rescued_meals_week()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_week_start timestamptz;
  v_preordered int := 0;
  v_preorderable int := 0;
BEGIN
  v_week_start :=
    (date_trunc('week', (timezone('Asia/Kolkata', now())))
      AT TIME ZONE 'Asia/Kolkata');

  SELECT COALESCE(SUM(q), 0)::int
  INTO v_preordered
  FROM (
    SELECT GREATEST(
      1,
      COALESCE(NULLIF(elem->>'quantity', '')::int, 1)
    ) AS q
    FROM public.orders o
    CROSS JOIN LATERAL jsonb_array_elements(
      CASE
        WHEN o.items IS NULL OR btrim(o.items) = '' THEN '[]'::jsonb
        WHEN left(btrim(o.items), 1) = '[' THEN o.items::jsonb
        ELSE '[]'::jsonb
      END
    ) AS elem
    WHERE o.created_at >= v_week_start
      AND lower(coalesce(o.status, '')) NOT LIKE '%cancel%'
      AND lower(coalesce(o.status, '')) NOT LIKE '%reject%'
      AND (
        NULLIF(btrim(coalesce(elem->>'selected_date', elem->>'selectedDate', '')), '') IS NOT NULL
        OR (
          NULLIF(btrim(coalesce(elem->>'time_slot', elem->>'timeSlot', '')), '') IS NOT NULL
          AND lower(btrim(coalesce(elem->>'time_slot', elem->>'timeSlot', ''))) NOT IN ('asap', 'now')
          AND lower(btrim(coalesce(elem->>'time_slot', elem->>'timeSlot', ''))) NOT LIKE '%asap%'
        )
      )
  ) preordered;

  SELECT COALESCE(SUM(GREATEST(0, COALESCE(m.quantity, 0))), 0)::int
  INTO v_preorderable
  FROM public.meals m
  WHERE lower(coalesce(m.status, '')) = 'available'
    AND COALESCE(m.quantity, 0) > 0
    AND (
      NULLIF(btrim(coalesce(m.time_slot, '')), '') IS NOT NULL
      AND lower(btrim(m.time_slot)) NOT IN ('asap', 'now')
      AND lower(btrim(m.time_slot)) NOT LIKE '%asap%'
    );

  RETURN jsonb_build_object(
    'rescued_plates', v_preordered,
    'preordered_plates', v_preordered,
    'on_offer_plates', v_preorderable,
    'preorderable_plates', v_preorderable,
    'week_start', v_week_start
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_rescued_meals_week() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_rescued_meals_week() TO anon, authenticated, service_role;
