-- Readiness hardening: rate limits, SLA escalate, CSAT, welcome drip,
-- meals.updated_at, descriptive forecast / churn / fraud signals.

ALTER TABLE public.meals
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE OR REPLACE FUNCTION public.touch_meals_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS meals_touch_updated_at ON public.meals;
CREATE TRIGGER meals_touch_updated_at
  BEFORE UPDATE ON public.meals
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_meals_updated_at();

CREATE TABLE IF NOT EXISTS public.api_rate_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  bucket text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS api_rate_events_bucket_time_idx
  ON public.api_rate_events (bucket, created_at DESC);

ALTER TABLE public.api_rate_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.api_rate_events FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.api_rate_events TO service_role;

CREATE OR REPLACE FUNCTION public.assert_user_rate_limit(
  p_scope text,
  p_limit integer DEFAULT 8,
  p_window_minutes integer DEFAULT 15
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_scope text := lower(trim(coalesce(p_scope, 'checkout')));
  v_bucket text;
  v_hits integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sign in required';
  END IF;
  v_bucket := v_scope || ':' || v_uid::text;
  DELETE FROM public.api_rate_events WHERE created_at < now() - interval '24 hours';
  INSERT INTO public.api_rate_events (bucket) VALUES (v_bucket);
  SELECT count(*) INTO v_hits
  FROM public.api_rate_events
  WHERE bucket = v_bucket
    AND created_at > now() - make_interval(mins => greatest(1, least(coalesce(p_window_minutes, 15), 120)));
  IF v_hits > greatest(1, least(coalesce(p_limit, 8), 40)) THEN
    RAISE EXCEPTION 'Too many attempts. Wait a few minutes and try again.';
  END IF;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.assert_user_rate_limit(text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assert_user_rate_limit(text, integer, integer) TO authenticated, service_role;

ALTER TABLE public.support_tickets
  ADD COLUMN IF NOT EXISTS csat_score smallint;

CREATE OR REPLACE FUNCTION public.submit_ticket_csat(p_ticket_id uuid, p_score integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_score integer := coalesce(p_score, 0);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in required';
  END IF;
  IF v_score < 1 OR v_score > 5 THEN
    RAISE EXCEPTION 'Score must be 1 to 5';
  END IF;
  UPDATE public.support_tickets
  SET csat_score = v_score, updated_at = now()
  WHERE id = p_ticket_id
    AND created_by = auth.uid()
    AND status IN ('resolved', 'closed')
    AND csat_score IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This ticket cannot be rated';
  END IF;
  RETURN jsonb_build_object('ok', true, 'score', v_score);
END;
$$;

REVOKE ALL ON FUNCTION public.submit_ticket_csat(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_ticket_csat(uuid, integer) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ops_escalate_overdue_tickets()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n integer := 0;
BEGIN
  IF auth.uid() IS NOT NULL
     AND auth.role() IS DISTINCT FROM 'service_role'
     AND NOT public.ops_has_permission('tickets') THEN
    RAISE EXCEPTION 'Tickets ops permission required';
  END IF;
  UPDATE public.support_tickets
  SET
    priority = 'urgent',
    assigned_to = COALESCE(assigned_to, auth.uid()),
    updated_at = now()
  WHERE status IN ('open', 'pending_ops')
    AND sla_due_at < now()
    AND coalesce(priority, 'normal') <> 'urgent';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('escalated', v_n);
END;
$$;

REVOKE ALL ON FUNCTION public.ops_escalate_overdue_tickets() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ops_escalate_overdue_tickets() TO authenticated, service_role;

CREATE TABLE IF NOT EXISTS public.user_lifecycle_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  kind text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, kind)
);

ALTER TABLE public.user_lifecycle_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_lifecycle_events_self ON public.user_lifecycle_events
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

GRANT SELECT, INSERT ON public.user_lifecycle_events TO authenticated;
GRANT ALL ON public.user_lifecycle_events TO service_role;

CREATE OR REPLACE FUNCTION public.claim_welcome_drip()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in required';
  END IF;
  INSERT INTO public.user_lifecycle_events (user_id, kind)
  VALUES (auth.uid(), 'welcome')
  ON CONFLICT (user_id, kind) DO NOTHING
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'send', v_id IS NOT NULL);
END;
$$;

REVOKE ALL ON FUNCTION public.claim_welcome_drip() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_welcome_drip() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ops_readiness_signals(p_period text DEFAULT 'week')
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_period text := lower(trim(coalesce(p_period, 'week')));
  v_tz text := 'Asia/Kolkata';
  v_now timestamptz := now();
  v_start timestamptz;
  v_avg numeric := 0;
BEGIN
  IF NOT (
    public.ops_has_permission('dashboard')
    OR public.ops_has_permission('analytics')
    OR public.ops_has_permission('crm')
  ) THEN
    RAISE EXCEPTION 'Dashboard ops permission required';
  END IF;
  IF v_period NOT IN ('day', 'week', 'month') THEN
    v_period := 'week';
  END IF;
  IF v_period = 'day' THEN
    v_start := date_trunc('day', v_now AT TIME ZONE v_tz) AT TIME ZONE v_tz;
  ELSIF v_period = 'week' THEN
    v_start := date_trunc('day', (v_now AT TIME ZONE v_tz) - interval '6 days') AT TIME ZONE v_tz;
  ELSE
    v_start := date_trunc('month', v_now AT TIME ZONE v_tz) AT TIME ZONE v_tz;
  END IF;

  SELECT coalesce(avg(d.gmv), 0) INTO v_avg
  FROM (
    SELECT coalesce(sum(
      coalesce(
        NULLIF(to_jsonb(o)->>'total_price', '')::numeric,
        NULLIF(to_jsonb(o)->>'total_amount', '')::numeric,
        0
      )
    ), 0) AS gmv
    FROM public.orders o
    WHERE o.created_at >= v_now - interval '7 days'
      AND nullif(trim(coalesce(to_jsonb(o)->>'payment_id', '')), '') IS NOT NULL
    GROUP BY date_trunc('day', o.created_at AT TIME ZONE v_tz)
  ) d;

  RETURN jsonb_build_object(
    'sla_breached', (
      SELECT count(*) FROM public.support_tickets
      WHERE status IN ('open', 'pending_ops') AND sla_due_at < v_now
    ),
    'avg_csat', (
      SELECT coalesce(round(avg(csat_score)::numeric, 2), 0)
      FROM public.support_tickets WHERE csat_score IS NOT NULL
    ),
    'repeat_7d', (
      SELECT count(*) FROM (
        SELECT customer_id FROM public.orders
        WHERE created_at >= v_now - interval '7 days'
          AND nullif(trim(coalesce(to_jsonb(orders)->>'payment_id', '')), '') IS NOT NULL
        GROUP BY customer_id
        HAVING count(*) >= 2
      ) r
    ),
    'repeat_30d', (
      SELECT count(*) FROM (
        SELECT customer_id FROM public.orders
        WHERE created_at >= v_now - interval '30 days'
          AND nullif(trim(coalesce(to_jsonb(orders)->>'payment_id', '')), '') IS NOT NULL
        GROUP BY customer_id
        HAVING count(*) >= 2
      ) r
    ),
    'churn_21d', (
      SELECT count(*) FROM public.users u
      WHERE lower(u.role::text) IN ('customer', 'diner')
        AND coalesce(u.created_at, v_now) < v_now - interval '21 days'
        AND NOT EXISTS (
          SELECT 1 FROM public.orders o
          WHERE o.customer_id = u.id
            AND o.created_at >= v_now - interval '21 days'
            AND nullif(trim(coalesce(to_jsonb(o)->>'payment_id', '')), '') IS NOT NULL
        )
    ),
    'referred_accounts', (
      SELECT count(*) FROM public.users WHERE nullif(trim(coalesce(referred_by, '')), '') IS NOT NULL
    ),
    'organic_accounts', (
      SELECT count(*) FROM public.users WHERE nullif(trim(coalesce(referred_by, '')), '') IS NULL
        AND lower(role::text) IN ('customer', 'diner')
    ),
    'refund_velocity', (
      SELECT count(*) FROM public.orders
      WHERE created_at >= v_now - interval '7 days'
        AND (
          lower(coalesce(refund_status, '')) IN ('processed', 'failed', 'pending')
          OR lower(coalesce(status::text, '')) ~ '(cancel|refund)'
        )
        AND nullif(trim(coalesce(to_jsonb(orders)->>'payment_id', '')), '') IS NOT NULL
    ),
    'fraud_flags', (
      SELECT count(*) FROM (
        SELECT customer_id FROM public.orders
        WHERE created_at >= v_now - interval '7 days'
          AND lower(coalesce(status::text, '')) ~ '(cancel|refund)'
        GROUP BY customer_id
        HAVING count(*) >= 3
      ) f
    ),
    'forecast_gmv_7d', round(v_avg * 7, 2),
    'window_start', v_start
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ops_readiness_signals(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ops_readiness_signals(text) TO authenticated, service_role;

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
  PERFORM cron.unschedule('ops-escalate-overdue-tickets');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.schedule(
    'ops-escalate-overdue-tickets',
    '*/10 * * * *',
    $cron$SELECT public.ops_escalate_overdue_tickets();$cron$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron schedule skipped';
END $$;
