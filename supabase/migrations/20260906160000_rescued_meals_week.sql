-- Public "Saved from waste" stats for diner Home.
-- Counts flash-sale plates ordered this IST week + leftover plates still listed.

CREATE OR REPLACE FUNCTION public.get_rescued_meals_week()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_week_start timestamptz;
  v_rescued int := 0;
  v_on_offer int := 0;
BEGIN
  -- Monday 00:00 Asia/Kolkata → timestamptz
  v_week_start :=
    (date_trunc('week', (timezone('Asia/Kolkata', now())))
      AT TIME ZONE 'Asia/Kolkata');

  SELECT COALESCE(SUM(q), 0)::int
  INTO v_rescued
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
      AND lower(coalesce(elem->>'offer_type', '')) LIKE '%flash%'
  ) rescued;

  SELECT COALESCE(SUM(GREATEST(0, COALESCE(m.quantity, 0))), 0)::int
  INTO v_on_offer
  FROM public.meals m
  WHERE lower(coalesce(m.status, '')) = 'available'
    AND COALESCE(m.quantity, 0) > 0
    AND (
      lower(coalesce(m.offer_type, '')) LIKE '%flash%'
      OR NULLIF(btrim(coalesce(m.promo_code, '')), '') IS NOT NULL
    );

  RETURN jsonb_build_object(
    'rescued_plates', v_rescued,
    'on_offer_plates', v_on_offer,
    'week_start', v_week_start
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_rescued_meals_week() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_rescued_meals_week() TO anon, authenticated, service_role;
