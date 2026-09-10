-- Admin HQ: analytics + CRM directory + helper notes.
-- Dashboard / Analytics / CRM seats may read HQ metrics.

CREATE TABLE IF NOT EXISTS public.platform_crm_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_user_id uuid NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS platform_crm_notes_subject_idx
  ON public.platform_crm_notes (subject_user_id, created_at DESC);

ALTER TABLE public.platform_crm_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS platform_crm_notes_ops_select ON public.platform_crm_notes;
CREATE POLICY platform_crm_notes_ops_select ON public.platform_crm_notes
  FOR SELECT TO authenticated
  USING (
    public.ops_has_permission('crm')
    OR public.ops_has_permission('dashboard')
    OR public.is_platform_owner()
  );

GRANT SELECT ON public.platform_crm_notes TO authenticated;
GRANT ALL ON public.platform_crm_notes TO service_role;

CREATE OR REPLACE FUNCTION public.ops_create_helper_invite(
  p_permissions text[],
  p_label text DEFAULT NULL,
  p_expires_hours integer DEFAULT 72,
  p_max_uses integer DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_perms text[] := '{}';
  v_key text;
  v_code text;
  v_hours integer := greatest(1, least(coalesce(p_expires_hours, 72), 720));
  v_max integer := greatest(1, least(coalesce(p_max_uses, 1), 50));
  v_id uuid;
  v_expires timestamptz;
  v_allowed text[] := ARRAY[
    'dashboard', 'analytics', 'crm', 'packaging', 'fssai', 'brands', 'refunds', 'tickets', 'kyc'
  ];
BEGIN
  IF NOT public.is_platform_owner() THEN
    RAISE EXCEPTION 'Platform owner only';
  END IF;

  FOREACH v_key IN ARRAY coalesce(p_permissions, '{}'::text[])
  LOOP
    v_key := lower(trim(v_key));
    IF v_key = ANY (ARRAY['accounts', 'helpers']) THEN
      RAISE EXCEPTION 'Cannot grant accounts or helpers via invite';
    END IF;
    IF v_key = ANY (v_allowed) AND NOT (v_key = ANY (v_perms)) THEN
      v_perms := array_append(v_perms, v_key);
    END IF;
  END LOOP;

  IF coalesce(array_length(v_perms, 1), 0) = 0 THEN
    RAISE EXCEPTION 'Select at least one permission';
  END IF;

  LOOP
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.platform_ops_invites WHERE code = v_code);
  END LOOP;

  v_expires := now() + make_interval(hours => v_hours);

  INSERT INTO public.platform_ops_invites (
    code, permissions, label, created_by, expires_at, max_uses
  )
  VALUES (
    v_code, v_perms, nullif(trim(coalesce(p_label, '')), ''), auth.uid(), v_expires, v_max
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'id', v_id,
    'code', v_code,
    'permissions', to_jsonb(v_perms),
    'expires_at', v_expires,
    'max_uses', v_max,
    'deep_link_path', '/ops-invite?code=' || v_code
  );
END;
$$;

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
  IF NOT (
    public.ops_has_permission('dashboard')
    OR public.ops_has_permission('analytics')
    OR public.ops_has_permission('crm')
  ) THEN
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
        ELSE CASE
          WHEN coalesce(NULLIF(to_jsonb(o)->>'platform_margin', '')::numeric, 0) > 0
            THEN (to_jsonb(o)->>'platform_margin')::numeric
          ELSE round(
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
        END
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

CREATE OR REPLACE FUNCTION public.ops_admin_hq(p_period text DEFAULT 'day')
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
  v_snap jsonb;
BEGIN
  IF NOT (
    public.ops_has_permission('dashboard')
    OR public.ops_has_permission('analytics')
    OR public.ops_has_permission('crm')
  ) THEN
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

  v_snap := public.ops_transaction_snapshot(v_period);

  RETURN jsonb_build_object(
    'snapshot', v_snap,
    'period', v_period,
    'window_start', v_start,
    'user_count', (SELECT count(*) FROM public.users),
    'chef_count', (SELECT count(*) FROM public.users WHERE lower(role::text) = 'chef'),
    'diner_count', (SELECT count(*) FROM public.users WHERE lower(role::text) IN ('customer', 'diner')),
    'driver_count', (SELECT count(*) FROM public.users WHERE lower(role::text) = 'driver'),
    'new_users', (
      SELECT count(*) FROM public.users u
      WHERE coalesce(u.created_at, v_now) >= v_start AND coalesce(u.created_at, v_now) <= v_now
    ),
    'pending_kyc', (
      SELECT count(*)
      FROM public.users u
      WHERE lower(u.role::text) IN ('chef', 'driver')
        AND lower(coalesce(u.fssai_verification_status, 'unsubmitted')) <> 'verified'
    ),
    'pending_fssai', (
      SELECT count(*)
      FROM public.users u
      WHERE lower(u.role::text) = 'chef'
        AND lower(coalesce(u.fssai_verification_status, 'unsubmitted')) IN ('pending', 'unsubmitted', 'rejected')
    ),
    'open_tickets', (
      SELECT count(*) FROM public.support_tickets
      WHERE status IN ('open', 'pending_customer', 'pending_ops')
    ),
    'open_disputes', (
      SELECT count(*) FROM public.order_disputes
      WHERE status IN ('open', 'investigating', 'awaiting_refund')
    ),
    'failed_refunds', (
      SELECT count(*) FROM public.orders
      WHERE lower(coalesce(refund_status, '')) = 'failed'
    ),
    'live_meals', (
      SELECT count(*) FROM public.meals WHERE lower(coalesce(status, '')) = 'available'
    ),
    'users_by_role', coalesce((
      SELECT jsonb_agg(jsonb_build_object('role', r.role, 'label', r.role, 'count', r.n) ORDER BY r.n DESC)
      FROM (
        SELECT lower(u.role::text) AS role, count(*)::integer AS n
        FROM public.users u
        GROUP BY 1
      ) r
    ), '[]'::jsonb),
    'tickets_by_status', coalesce((
      SELECT jsonb_agg(jsonb_build_object('status', t.status, 'label', t.status, 'count', t.n) ORDER BY t.n DESC)
      FROM (
        SELECT status, count(*)::integer AS n
        FROM public.support_tickets
        GROUP BY 1
      ) t
    ), '[]'::jsonb),
    'top_kitchens', coalesce((
      SELECT jsonb_agg(row_to_json(k)::jsonb)
      FROM (
        SELECT
          o.chef_id,
          coalesce(
            nullif(trim(to_jsonb(cp)->>'local_kitchen_name'), ''),
            nullif(trim(u.name), ''),
            nullif(trim(u.full_name), ''),
            'Kitchen'
          ) AS name,
          count(*)::integer AS order_count,
          coalesce(sum(
            coalesce(
              NULLIF(to_jsonb(o)->>'total_price', '')::numeric,
              NULLIF(to_jsonb(o)->>'total_amount', '')::numeric,
              NULLIF(to_jsonb(o)->>'grand_total', '')::numeric,
              0
            )
          ), 0) AS gmv
        FROM public.orders o
        LEFT JOIN public.users u ON u.id = o.chef_id
        LEFT JOIN public.chef_profiles cp ON cp.user_id = o.chef_id
        WHERE o.created_at >= v_start
          AND o.created_at <= v_now
          AND nullif(trim(coalesce(to_jsonb(o)->>'payment_id', '')), '') IS NOT NULL
        GROUP BY o.chef_id, to_jsonb(cp)->>'local_kitchen_name', u.name, u.full_name
        ORDER BY gmv DESC
        LIMIT 8
      ) k
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ops_admin_hq(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ops_admin_hq(text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ops_crm_directory(
  p_role text DEFAULT 'all',
  p_search text DEFAULT '',
  p_limit integer DEFAULT 80
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text := lower(trim(coalesce(p_role, 'all')));
  v_search text := lower(trim(coalesce(p_search, '')));
  v_limit integer := greatest(1, least(coalesce(p_limit, 80), 200));
BEGIN
  IF NOT (
    public.ops_has_permission('crm')
    OR public.ops_has_permission('dashboard')
    OR public.ops_has_permission('accounts')
    OR public.is_platform_owner()
  ) THEN
    RAISE EXCEPTION 'CRM ops permission required';
  END IF;

  IF v_role NOT IN ('all', 'chef', 'customer', 'diner', 'driver', 'admin') THEN
    v_role := 'all';
  END IF;

  RETURN coalesce((
    SELECT jsonb_agg(row_to_json(q)::jsonb)
    FROM (
      SELECT
        u.id,
        u.role,
        u.name,
        u.full_name,
        u.email,
        u.phone,
        u.account_status,
        u.fssai_verification_status,
        u.created_at,
        to_jsonb(cp)->>'local_kitchen_name' AS kitchen_name,
        coalesce(ord.order_count, 0) AS order_count,
        coalesce(ord.gmv, 0) AS gmv,
        ord.last_order_at,
        coalesce(tk.open_tickets, 0) AS open_tickets,
        note.body AS last_note
      FROM public.users u
      LEFT JOIN public.chef_profiles cp ON cp.user_id = u.id
      LEFT JOIN LATERAL (
        SELECT
          count(*)::integer AS order_count,
          coalesce(sum(
            coalesce(
              NULLIF(to_jsonb(o)->>'total_price', '')::numeric,
              NULLIF(to_jsonb(o)->>'total_amount', '')::numeric,
              NULLIF(to_jsonb(o)->>'grand_total', '')::numeric,
              0
            )
          ), 0) AS gmv,
          max(o.created_at) AS last_order_at
        FROM public.orders o
        WHERE (o.customer_id = u.id OR o.chef_id = u.id)
          AND nullif(trim(coalesce(to_jsonb(o)->>'payment_id', '')), '') IS NOT NULL
      ) ord ON true
      LEFT JOIN LATERAL (
        SELECT count(*)::integer AS open_tickets
        FROM public.support_tickets t
        WHERE t.created_by = u.id
          AND t.status IN ('open', 'pending_customer', 'pending_ops')
      ) tk ON true
      LEFT JOIN LATERAL (
        SELECT n.body
        FROM public.platform_crm_notes n
        WHERE n.subject_user_id = u.id
        ORDER BY n.created_at DESC
        LIMIT 1
      ) note ON true
      WHERE (v_role = 'all'
        OR (v_role IN ('customer', 'diner') AND lower(u.role::text) IN ('customer', 'diner'))
        OR lower(u.role::text) = v_role)
        AND (
          v_search = ''
          OR lower(coalesce(u.name, '')) LIKE '%' || v_search || '%'
          OR lower(coalesce(u.full_name, '')) LIKE '%' || v_search || '%'
          OR lower(coalesce(u.email, '')) LIKE '%' || v_search || '%'
          OR coalesce(u.phone, '') LIKE '%' || v_search || '%'
          OR lower(coalesce(to_jsonb(cp)->>'local_kitchen_name', '')) LIKE '%' || v_search || '%'
        )
      ORDER BY coalesce(ord.last_order_at, u.created_at) DESC NULLS LAST
      LIMIT v_limit
    ) q
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.ops_crm_directory(text, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ops_crm_directory(text, text, integer) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ops_crm_add_note(p_user_id uuid, p_body text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_body text := trim(coalesce(p_body, ''));
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.ops_has_permission('crm')
    OR public.ops_has_permission('dashboard')
    OR public.is_platform_owner()
  ) THEN
    RAISE EXCEPTION 'CRM ops permission required';
  END IF;
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Account required';
  END IF;
  IF char_length(v_body) < 2 THEN
    RAISE EXCEPTION 'Note is too short';
  END IF;
  INSERT INTO public.platform_crm_notes (subject_user_id, author_id, body)
  VALUES (p_user_id, auth.uid(), left(v_body, 2000))
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END;
$$;

REVOKE ALL ON FUNCTION public.ops_crm_add_note(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ops_crm_add_note(uuid, text) TO authenticated, service_role;
