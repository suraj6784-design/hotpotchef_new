-- Admin dashboard: platform margin earned (15% of food + packaging on delivered paid orders).

CREATE OR REPLACE FUNCTION public.ops_transaction_snapshot(p_period text DEFAULT 'day')
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_period text := lower(trim(coalesce(p_period, 'day')));
  v_tz text := 'Asia/Kolkata';
  v_now timestamptz := now();
  v_start timestamptz;
  v_gmv numeric := 0;
  v_count integer := 0;
  v_delivered integer := 0;
  v_cancelled integer := 0;
  v_delivery numeric := 0;
  v_margin numeric := 0;
  v_series jsonb := '[]'::jsonb;
  v_recent jsonb := '[]'::jsonb;
BEGIN
  IF NOT public.ops_has_permission('dashboard') THEN
    RAISE EXCEPTION 'Dashboard ops permission required';
  END IF;

  IF v_period NOT IN ('day', 'week', 'month') THEN
    RAISE EXCEPTION 'period must be day, week, or month';
  END IF;

  IF v_period = 'day' THEN
    v_start := date_trunc('day', v_now AT TIME ZONE v_tz) AT TIME ZONE v_tz;
  ELSIF v_period = 'week' THEN
    v_start := date_trunc('day', (v_now AT TIME ZONE v_tz) - interval '6 days') AT TIME ZONE v_tz;
  ELSE
    v_start := date_trunc('month', v_now AT TIME ZONE v_tz) AT TIME ZONE v_tz;
  END IF;

  SELECT
    coalesce(sum(
      coalesce(
        NULLIF(to_jsonb(o)->>'total_price', '')::numeric,
        NULLIF(to_jsonb(o)->>'total_amount', '')::numeric,
        NULLIF(to_jsonb(o)->>'grand_total', '')::numeric,
        0
      )
    ), 0),
    count(*)::integer,
    count(*) FILTER (
      WHERE lower(coalesce(o.status::text, '')) ~ '(delivered|complet)'
        AND lower(coalesce(o.status::text, '')) !~ 'undeliver'
    )::integer,
    count(*) FILTER (
      WHERE lower(coalesce(o.status::text, '')) ~ '(cancel|refund|reject)'
    )::integer,
    coalesce(sum(coalesce(NULLIF(to_jsonb(o)->>'delivery_fee', '')::numeric, 0)), 0),
    coalesce(sum(
      CASE
        WHEN lower(coalesce(o.status::text, '')) ~ '(cancel|refund|reject)' THEN 0
        WHEN lower(coalesce(o.status::text, '')) !~ '(delivered|complet)'
          OR lower(coalesce(o.status::text, '')) ~ 'undeliver' THEN 0
        ELSE coalesce(
          NULLIF(to_jsonb(o)->>'platform_margin', '')::numeric,
          round(
            0.15 * greatest(
              0,
              coalesce(
                NULLIF(to_jsonb(o)->>'total_price', '')::numeric,
                NULLIF(to_jsonb(o)->>'total_amount', '')::numeric,
                NULLIF(to_jsonb(o)->>'grand_total', '')::numeric,
                0
              )
              - coalesce(NULLIF(to_jsonb(o)->>'delivery_fee', '')::numeric, 0)
              - coalesce(NULLIF(to_jsonb(o)->>'tip_amount', '')::numeric, 0)
            ),
            2
          )
        )
      END
    ), 0)
  INTO v_gmv, v_count, v_delivered, v_cancelled, v_delivery, v_margin
  FROM public.orders o
  WHERE o.created_at >= v_start
    AND o.created_at <= v_now
    AND nullif(trim(coalesce(to_jsonb(o)->>'payment_id', '')), '') IS NOT NULL;

  SELECT coalesce(jsonb_agg(row_to_json(s)::jsonb ORDER BY s.bucket_date), '[]'::jsonb)
  INTO v_series
  FROM (
    SELECT
      (date_trunc('day', o.created_at AT TIME ZONE v_tz))::date AS bucket_date,
      coalesce(sum(
        coalesce(
          NULLIF(to_jsonb(o)->>'total_price', '')::numeric,
          NULLIF(to_jsonb(o)->>'total_amount', '')::numeric,
          NULLIF(to_jsonb(o)->>'grand_total', '')::numeric,
          0
        )
      ), 0) AS gmv,
      count(*)::integer AS order_count
    FROM public.orders o
    WHERE o.created_at >= v_start
      AND o.created_at <= v_now
      AND nullif(trim(coalesce(to_jsonb(o)->>'payment_id', '')), '') IS NOT NULL
    GROUP BY 1
  ) s;

  SELECT coalesce(jsonb_agg(row_to_json(r)::jsonb), '[]'::jsonb)
  INTO v_recent
  FROM (
    SELECT
      o.id,
      NULL::text AS order_id,
      o.created_at,
      o.status,
      coalesce(
        NULLIF(to_jsonb(o)->>'total_price', '')::numeric,
        NULLIF(to_jsonb(o)->>'total_amount', '')::numeric,
        NULLIF(to_jsonb(o)->>'grand_total', '')::numeric,
        0
      ) AS total,
      to_jsonb(o)->>'payment_id' AS payment_id,
      o.chef_id,
      o.customer_id
    FROM public.orders o
    WHERE o.created_at >= v_start
      AND o.created_at <= v_now
      AND nullif(trim(coalesce(to_jsonb(o)->>'payment_id', '')), '') IS NOT NULL
    ORDER BY o.created_at DESC
    LIMIT 25
  ) r;

  RETURN jsonb_build_object(
    'period', v_period,
    'timezone', v_tz,
    'window_start', v_start,
    'window_end', v_now,
    'gmv', v_gmv,
    'order_count', v_count,
    'delivered_count', v_delivered,
    'cancelled_count', v_cancelled,
    'delivery_fee_sum', v_delivery,
    'platform_margin_sum', v_margin,
    'avg_ticket', CASE WHEN v_count > 0 THEN round(v_gmv / v_count, 2) ELSE 0 END,
    'series', v_series,
    'recent', v_recent
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.ops_transaction_snapshot(text) TO authenticated, service_role;
