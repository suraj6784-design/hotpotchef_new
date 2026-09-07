-- Platform owner (suraj6784@gmail.com) + scoped helper invites + account status + transaction snapshot.

-- ---------------------------------------------------------------------------
-- Extend platform_ops seats
-- ---------------------------------------------------------------------------
ALTER TABLE public.platform_ops
  ADD COLUMN IF NOT EXISTS seat_role text NOT NULL DEFAULT 'helper',
  ADD COLUMN IF NOT EXISTS permissions text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS created_by uuid,
  ADD COLUMN IF NOT EXISTS revoked_at timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'platform_ops_seat_role_check'
  ) THEN
    ALTER TABLE public.platform_ops
      ADD CONSTRAINT platform_ops_seat_role_check
      CHECK (seat_role IN ('owner', 'helper'));
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Helper invites
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.platform_ops_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL,
  permissions text[] NOT NULL DEFAULT '{}',
  label text,
  created_by uuid NOT NULL,
  expires_at timestamptz NOT NULL,
  max_uses integer NOT NULL DEFAULT 1,
  use_count integer NOT NULL DEFAULT 0,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT platform_ops_invites_code_unique UNIQUE (code),
  CONSTRAINT platform_ops_invites_max_uses_check CHECK (max_uses >= 1),
  CONSTRAINT platform_ops_invites_use_count_check CHECK (use_count >= 0)
);

CREATE INDEX IF NOT EXISTS platform_ops_invites_active_idx
  ON public.platform_ops_invites (expires_at)
  WHERE revoked_at IS NULL;

ALTER TABLE public.platform_ops_invites ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.platform_ops_invites TO authenticated;
GRANT ALL ON public.platform_ops_invites TO service_role;

-- ---------------------------------------------------------------------------
-- Account status on users
-- ---------------------------------------------------------------------------
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS account_status text NOT NULL DEFAULT 'active';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'users_account_status_check'
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_account_status_check
      CHECK (account_status IN ('active', 'suspended'));
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Owner / ops / permission helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.platform_owner_email()
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 'suraj6784@gmail.com'::text;
$$;

CREATE OR REPLACE FUNCTION public.is_platform_owner()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.platform_ops po
    JOIN auth.users au ON au.id = po.user_id
    WHERE po.user_id = auth.uid()
      AND po.revoked_at IS NULL
      AND po.seat_role = 'owner'
      AND lower(coalesce(au.email, '')) = lower(public.platform_owner_email())
  );
$$;

CREATE OR REPLACE FUNCTION public.is_platform_ops()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.platform_ops po
    WHERE po.user_id = auth.uid()
      AND po.revoked_at IS NULL
  );
$$;

CREATE OR REPLACE FUNCTION public.ops_has_permission(p_key text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key text := lower(trim(coalesce(p_key, '')));
  v_role text;
  v_perms text[];
BEGIN
  IF auth.uid() IS NULL OR v_key = '' THEN
    RETURN false;
  END IF;

  IF public.is_platform_owner() THEN
    RETURN true;
  END IF;

  SELECT seat_role, permissions
  INTO v_role, v_perms
  FROM public.platform_ops
  WHERE user_id = auth.uid()
    AND revoked_at IS NULL
  LIMIT 1;

  IF v_role IS NULL THEN
    RETURN false;
  END IF;

  IF v_role = 'owner' THEN
    RETURN true;
  END IF;

  RETURN v_key = ANY (
    SELECT lower(trim(x)) FROM unnest(coalesce(v_perms, '{}'::text[])) AS x
  );
END;
$$;

REVOKE ALL ON FUNCTION public.platform_owner_email() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_platform_owner() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_platform_ops() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ops_has_permission(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_owner_email() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_platform_owner() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_platform_ops() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ops_has_permission(text) TO authenticated, service_role;

-- Seed exclusive owner; demote/remove other seats that claimed owner.
UPDATE public.platform_ops po
SET seat_role = 'helper',
    revoked_at = coalesce(po.revoked_at, now())
WHERE po.seat_role = 'owner'
  AND po.user_id NOT IN (
    SELECT id FROM auth.users WHERE lower(email) = lower(public.platform_owner_email())
  );

DELETE FROM public.platform_ops
WHERE user_id NOT IN (
  SELECT id FROM auth.users WHERE lower(email) = lower(public.platform_owner_email())
)
AND seat_role = 'owner';

INSERT INTO public.platform_ops (user_id, note, seat_role, permissions)
SELECT id, 'exclusive HotPotChef platform owner', 'owner', '{}'::text[]
FROM auth.users
WHERE lower(email) = lower(public.platform_owner_email())
ON CONFLICT (user_id) DO UPDATE
SET
  note = EXCLUDED.note,
  seat_role = 'owner',
  permissions = '{}'::text[],
  revoked_at = NULL;

-- RLS: members see own seat; owner sees all seats + invites
DROP POLICY IF EXISTS platform_ops_select_self ON public.platform_ops;
CREATE POLICY platform_ops_select_self ON public.platform_ops
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid() OR public.is_platform_owner());

DROP POLICY IF EXISTS platform_ops_invites_select_owner ON public.platform_ops_invites;
CREATE POLICY platform_ops_invites_select_owner ON public.platform_ops_invites
  FOR SELECT
  TO authenticated
  USING (public.is_platform_owner());

-- ---------------------------------------------------------------------------
-- Invite create / redeem / revoke
-- ---------------------------------------------------------------------------
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
    'dashboard', 'packaging', 'fssai', 'brands', 'refunds', 'tickets', 'kyc'
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

CREATE OR REPLACE FUNCTION public.ops_redeem_helper_invite(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text := upper(trim(coalesce(p_code, '')));
  v_inv public.platform_ops_invites%ROWTYPE;
  v_status text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in required';
  END IF;

  SELECT account_status INTO v_status FROM public.users WHERE id = auth.uid();
  IF lower(coalesce(v_status, 'active')) = 'suspended' THEN
    RAISE EXCEPTION 'Account suspended';
  END IF;

  IF public.is_platform_owner() THEN
    RAISE EXCEPTION 'Owner already has full access';
  END IF;

  SELECT * INTO v_inv
  FROM public.platform_ops_invites
  WHERE code = v_code
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid invite code';
  END IF;
  IF v_inv.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'Invite revoked';
  END IF;
  IF v_inv.expires_at < now() THEN
    RAISE EXCEPTION 'Invite expired';
  END IF;
  IF v_inv.use_count >= v_inv.max_uses THEN
    RAISE EXCEPTION 'Invite already used';
  END IF;

  INSERT INTO public.platform_ops (user_id, note, seat_role, permissions, created_by, revoked_at)
  VALUES (
    auth.uid(),
    coalesce(v_inv.label, 'helper via invite ' || v_code),
    'helper',
    v_inv.permissions,
    v_inv.created_by,
    NULL
  )
  ON CONFLICT (user_id) DO UPDATE
  SET
    seat_role = 'helper',
    permissions = EXCLUDED.permissions,
    note = EXCLUDED.note,
    created_by = EXCLUDED.created_by,
    revoked_at = NULL;

  UPDATE public.platform_ops_invites
  SET use_count = use_count + 1
  WHERE id = v_inv.id;

  RETURN jsonb_build_object(
    'ok', true,
    'permissions', to_jsonb(v_inv.permissions),
    'code', v_code
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.ops_revoke_helper(p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_platform_owner() THEN
    RAISE EXCEPTION 'Platform owner only';
  END IF;
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user required';
  END IF;
  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot revoke own owner seat';
  END IF;

  UPDATE public.platform_ops
  SET revoked_at = now()
  WHERE user_id = p_user_id
    AND seat_role = 'helper';

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.ops_revoke_invite(p_invite_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_platform_owner() THEN
    RAISE EXCEPTION 'Platform owner only';
  END IF;

  UPDATE public.platform_ops_invites
  SET revoked_at = now()
  WHERE id = p_invite_id
    AND revoked_at IS NULL;

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.ops_set_user_role(p_user_id uuid, p_role text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text := initcap(lower(trim(coalesce(p_role, ''))));
  v_email text;
BEGIN
  IF NOT public.is_platform_owner() THEN
    RAISE EXCEPTION 'Platform owner only';
  END IF;

  IF v_role NOT IN ('Customer', 'Chef', 'Driver') THEN
    RAISE EXCEPTION 'Invalid role';
  END IF;

  SELECT lower(email) INTO v_email FROM auth.users WHERE id = p_user_id;
  IF v_email = lower(public.platform_owner_email()) THEN
    RAISE EXCEPTION 'Cannot change owner account role via ops';
  END IF;

  UPDATE public.users
  SET role = v_role
  WHERE id = p_user_id;

  UPDATE auth.users
  SET raw_user_meta_data =
    coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('role', v_role)
  WHERE id = p_user_id;

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.ops_set_account_status(p_user_id uuid, p_status text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text := lower(trim(coalesce(p_status, '')));
  v_email text;
BEGIN
  IF NOT public.is_platform_owner() THEN
    RAISE EXCEPTION 'Platform owner only';
  END IF;

  IF v_status NOT IN ('active', 'suspended') THEN
    RAISE EXCEPTION 'Invalid account status';
  END IF;

  SELECT lower(email) INTO v_email FROM auth.users WHERE id = p_user_id;
  IF v_email = lower(public.platform_owner_email()) THEN
    RAISE EXCEPTION 'Cannot suspend owner account';
  END IF;

  UPDATE public.users
  SET account_status = v_status
  WHERE id = p_user_id;

  RETURN FOUND;
END;
$$;

-- ---------------------------------------------------------------------------
-- Permission-gate existing ops RPCs
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ops_set_packaging_request_status(
  p_request_id uuid,
  p_status text,
  p_ops_note text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text := trim(p_status);
BEGIN
  IF auth.uid() IS NULL OR NOT public.ops_has_permission('packaging') THEN
    RAISE EXCEPTION 'Packaging ops permission required';
  END IF;

  IF lower(v_status) NOT IN (
    'open', 'confirmed', 'packed', 'out for delivery', 'fulfilled', 'rejected', 'cancelled'
  ) THEN
    RAISE EXCEPTION 'Invalid packaging status';
  END IF;

  v_status := CASE lower(v_status)
    WHEN 'open' THEN 'Open'
    WHEN 'confirmed' THEN 'Confirmed'
    WHEN 'packed' THEN 'Packed'
    WHEN 'out for delivery' THEN 'Out for Delivery'
    WHEN 'fulfilled' THEN 'Fulfilled'
    WHEN 'rejected' THEN 'Rejected'
    WHEN 'cancelled' THEN 'Cancelled'
    ELSE v_status
  END;

  UPDATE public.customer_requests
  SET
    status = v_status,
    ops_note = COALESCE(p_ops_note, ops_note),
    ops_updated_at = now(),
    ops_updated_by = auth.uid()
  WHERE id = p_request_id
    AND (
      lower(coalesce(service_type, '')) = 'packaging'
      OR lower(coalesce(request_type, '')) IN ('packaging', 'supply')
      OR coalesce(description, '') ~* 'SUP-[A-Z0-9]+'
    );

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.ops_set_fssai_status(
  p_chef_id uuid,
  p_status text,
  p_review_note text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text := lower(trim(p_status));
BEGIN
  IF auth.uid() IS NULL OR NOT public.ops_has_permission('fssai') THEN
    RAISE EXCEPTION 'FSSAI ops permission required';
  END IF;

  IF v_status NOT IN ('pending', 'verified', 'rejected', 'unsubmitted') THEN
    RAISE EXCEPTION 'Invalid FSSAI verification status';
  END IF;

  UPDATE public.users
  SET
    fssai_verification_status = v_status,
    fssai_review_note = COALESCE(p_review_note, fssai_review_note),
    fssai_verified_at = CASE WHEN v_status = 'verified' THEN now() ELSE NULL END,
    fssai_reviewed_by = auth.uid()
  WHERE id = p_chef_id;

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.ops_set_ticket_status(
  p_ticket_id uuid,
  p_status text,
  p_note text DEFAULT NULL
)
RETURNS public.support_tickets
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.support_tickets;
  v_status text := lower(trim(COALESCE(p_status, '')));
BEGIN
  IF NOT public.ops_has_permission('tickets') THEN
    RAISE EXCEPTION 'Tickets ops permission required';
  END IF;
  IF v_status NOT IN ('open', 'pending_customer', 'pending_ops', 'resolved', 'closed') THEN
    RAISE EXCEPTION 'Invalid ticket status';
  END IF;

  UPDATE public.support_tickets
  SET
    status = v_status,
    first_response_at = COALESCE(first_response_at, now()),
    resolved_at = CASE WHEN v_status IN ('resolved', 'closed') THEN COALESCE(resolved_at, now()) ELSE NULL END,
    assigned_to = COALESCE(assigned_to, auth.uid()),
    updated_at = now(),
    last_message_at = now()
  WHERE id = p_ticket_id
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Ticket not found';
  END IF;

  IF NULLIF(trim(COALESCE(p_note, '')), '') IS NOT NULL THEN
    INSERT INTO public.support_ticket_messages (ticket_id, author_id, body, is_internal)
    VALUES (v_row.id, auth.uid(), trim(p_note), true);
  END IF;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.ops_set_dispute_status(
  p_dispute_id uuid,
  p_status text,
  p_resolution_note text DEFAULT NULL
)
RETURNS public.order_disputes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.order_disputes;
  v_status text := lower(trim(COALESCE(p_status, '')));
BEGIN
  IF NOT public.ops_has_permission('refunds') THEN
    RAISE EXCEPTION 'Refunds ops permission required';
  END IF;
  IF v_status NOT IN ('open', 'investigating', 'awaiting_refund', 'resolved', 'rejected') THEN
    RAISE EXCEPTION 'Invalid dispute status';
  END IF;

  UPDATE public.order_disputes
  SET
    status = v_status,
    resolution_note = COALESCE(NULLIF(trim(COALESCE(p_resolution_note, '')), ''), resolution_note),
    resolved_at = CASE WHEN v_status IN ('resolved', 'rejected') THEN COALESCE(resolved_at, now()) ELSE NULL END,
    updated_at = now()
  WHERE id = p_dispute_id
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Dispute not found';
  END IF;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_set_ad_campaign_status(
  p_campaign_id uuid,
  p_status text,
  p_review_note text DEFAULT NULL,
  p_package_amount_paise integer DEFAULT NULL,
  p_package_label text DEFAULT NULL,
  p_starts_at timestamptz DEFAULT NULL,
  p_ends_at timestamptz DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role'
     AND NOT public.ops_has_permission('brands') THEN
    RAISE EXCEPTION 'Brands ops permission required';
  END IF;

  IF p_status NOT IN ('draft', 'pending_review', 'live', 'ended') THEN
    RAISE EXCEPTION 'Invalid campaign status';
  END IF;

  UPDATE public.ad_campaigns
  SET
    status = p_status,
    review_note = COALESCE(p_review_note, review_note),
    package_amount_paise = COALESCE(p_package_amount_paise, package_amount_paise),
    package_label = COALESCE(p_package_label, package_label),
    starts_at = COALESCE(p_starts_at, starts_at),
    ends_at = COALESCE(p_ends_at, ends_at),
    reviewed_at = CASE
      WHEN p_status IN ('live', 'ended', 'draft') THEN now()
      ELSE reviewed_at
    END,
    updated_at = now()
  WHERE id = p_campaign_id;

  RETURN FOUND;
END;
$$;

-- ---------------------------------------------------------------------------
-- Transaction snapshot (IST windows)
-- ---------------------------------------------------------------------------
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
    coalesce(sum(coalesce(NULLIF(to_jsonb(o)->>'delivery_fee', '')::numeric, 0)), 0)
  INTO v_gmv, v_count, v_delivered, v_cancelled, v_delivery
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
      -- orders store the UUID in id only (no order_id column)
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
    'avg_ticket', CASE WHEN v_count > 0 THEN round(v_gmv / v_count, 2) ELSE 0 END,
    'series', v_series,
    'recent', v_recent
  );
END;
$$;

-- Fix typo if I introduced payment of_id - wait I need to fix that in the migration!
-- I'll fix in a search replace after write.

GRANT EXECUTE ON FUNCTION public.ops_create_helper_invite(text[], text, integer, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ops_redeem_helper_invite(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ops_revoke_helper(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ops_revoke_invite(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ops_set_user_role(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ops_set_account_status(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ops_transaction_snapshot(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ops_set_packaging_request_status(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ops_set_fssai_status(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ops_set_ticket_status(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ops_set_dispute_status(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.platform_set_ad_campaign_status(
  uuid, text, text, integer, text, timestamptz, timestamptz
) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
