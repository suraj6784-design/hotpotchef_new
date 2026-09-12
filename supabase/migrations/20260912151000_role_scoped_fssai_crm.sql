-- FSSAI is a kitchen licence. CRM/HQ must not treat diners or drivers as FSSAI-pending,
-- and chef GMV must be kitchen orders (not diner spend).

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
      WHERE (
        lower(u.role::text) IN ('chef', 'cook')
        AND lower(coalesce(u.fssai_verification_status, 'unsubmitted')) <> 'verified'
      ) OR (
        lower(u.role::text) = 'driver'
        AND (
          coalesce(nullif(trim(to_jsonb(u)->>'aadhaar_masked'), ''), '') = ''
          OR coalesce(nullif(trim(to_jsonb(u)->>'vehicle_type'), ''), '') = ''
          OR coalesce(nullif(trim(to_jsonb(u)->>'pan_number'), ''), '') = ''
        )
      )
    ),
    'pending_fssai', (
      SELECT count(*)
      FROM public.users u
      WHERE lower(u.role::text) IN ('chef', 'cook')
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
        CASE
          WHEN lower(u.role::text) IN ('chef', 'cook') THEN u.fssai_verification_status
          ELSE NULL
        END AS fssai_verification_status,
        u.created_at,
        CASE
          WHEN lower(u.role::text) IN ('chef', 'cook') THEN to_jsonb(cp)->>'local_kitchen_name'
          ELSE NULL
        END AS kitchen_name,
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
        WHERE CASE
            WHEN lower(u.role::text) IN ('chef', 'cook') THEN o.chef_id = u.id
            WHEN lower(u.role::text) = 'driver' THEN false
            ELSE o.customer_id = u.id
          END
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
          OR (
            lower(u.role::text) IN ('chef', 'cook')
            AND lower(coalesce(to_jsonb(cp)->>'local_kitchen_name', '')) LIKE '%' || v_search || '%'
          )
        )
      ORDER BY coalesce(ord.last_order_at, u.created_at) DESC NULLS LAST
      LIMIT v_limit
    ) q
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.ops_crm_directory(text, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ops_crm_directory(text, text, integer) TO authenticated, service_role;
