-- Support tickets, disputes, society address fields, gate instructions, ops queues.

ALTER TABLE public.user_addresses
  ADD COLUMN IF NOT EXISTS wing text,
  ADD COLUMN IF NOT EXISTS flat_no text,
  ADD COLUMN IF NOT EXISTS society_name text,
  ADD COLUMN IF NOT EXISTS gate_instructions text;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS wing text,
  ADD COLUMN IF NOT EXISTS flat_no text,
  ADD COLUMN IF NOT EXISTS society_name text,
  ADD COLUMN IF NOT EXISTS gate_instructions text,
  ADD COLUMN IF NOT EXISTS delivery_otp text;

CREATE TABLE IF NOT EXISTS public.support_tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  public_id text UNIQUE NOT NULL,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  order_number text,
  subject text NOT NULL,
  body text NOT NULL,
  channel text NOT NULL DEFAULT 'in_app'
    CHECK (channel IN ('in_app', 'email', 'whatsapp')),
  category text NOT NULL DEFAULT 'general'
    CHECK (category IN ('general', 'order', 'refund', 'delivery', 'account', 'quality')),
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'pending_customer', 'pending_ops', 'resolved', 'closed')),
  priority text NOT NULL DEFAULT 'normal'
    CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  sla_due_at timestamptz NOT NULL DEFAULT (now() + interval '1 day'),
  first_response_at timestamptz,
  resolved_at timestamptz,
  assigned_to uuid REFERENCES auth.users(id),
  last_message_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.support_ticket_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES public.support_tickets(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES auth.users(id),
  body text NOT NULL,
  is_internal boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.order_disputes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  public_id text UNIQUE NOT NULL,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  opened_by uuid NOT NULL REFERENCES auth.users(id),
  support_ticket_id uuid REFERENCES public.support_tickets(id) ON DELETE SET NULL,
  reason text NOT NULL DEFAULT 'other'
    CHECK (reason IN ('missing_item', 'quality', 'late', 'wrong_order', 'refund_failed', 'chargeback', 'other')),
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'investigating', 'awaiting_refund', 'resolved', 'rejected')),
  resolution_note text,
  sla_due_at timestamptz NOT NULL DEFAULT (now() + interval '1 day'),
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS support_tickets_status_idx ON public.support_tickets (status, sla_due_at);
CREATE INDEX IF NOT EXISTS support_tickets_created_by_idx ON public.support_tickets (created_by, created_at DESC);
CREATE INDEX IF NOT EXISTS order_disputes_status_idx ON public.order_disputes (status, created_at DESC);
CREATE INDEX IF NOT EXISTS orders_refund_ops_idx ON public.orders (refund_status, updated_at DESC)
  WHERE refund_status IS NOT NULL;

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_ticket_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_disputes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS support_tickets_select_own_or_ops ON public.support_tickets;
CREATE POLICY support_tickets_select_own_or_ops ON public.support_tickets
  FOR SELECT TO authenticated
  USING (created_by = auth.uid() OR public.is_platform_ops());

DROP POLICY IF EXISTS support_tickets_insert_own ON public.support_tickets;
CREATE POLICY support_tickets_insert_own ON public.support_tickets
  FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid());

DROP POLICY IF EXISTS support_tickets_update_ops ON public.support_tickets;
CREATE POLICY support_tickets_update_ops ON public.support_tickets
  FOR UPDATE TO authenticated
  USING (public.is_platform_ops())
  WITH CHECK (public.is_platform_ops());

DROP POLICY IF EXISTS support_ticket_messages_select ON public.support_ticket_messages;
CREATE POLICY support_ticket_messages_select ON public.support_ticket_messages
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.support_tickets t
      WHERE t.id = ticket_id
        AND (t.created_by = auth.uid() OR public.is_platform_ops())
        AND (NOT is_internal OR public.is_platform_ops())
    )
  );

DROP POLICY IF EXISTS support_ticket_messages_insert ON public.support_ticket_messages;
CREATE POLICY support_ticket_messages_insert ON public.support_ticket_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    author_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.support_tickets t
      WHERE t.id = ticket_id
        AND (t.created_by = auth.uid() OR public.is_platform_ops())
    )
  );

DROP POLICY IF EXISTS order_disputes_select ON public.order_disputes;
CREATE POLICY order_disputes_select ON public.order_disputes
  FOR SELECT TO authenticated
  USING (opened_by = auth.uid() OR public.is_platform_ops());

DROP POLICY IF EXISTS order_disputes_insert ON public.order_disputes;
CREATE POLICY order_disputes_insert ON public.order_disputes
  FOR INSERT TO authenticated
  WITH CHECK (opened_by = auth.uid() OR public.is_platform_ops());

DROP POLICY IF EXISTS order_disputes_update_ops ON public.order_disputes;
CREATE POLICY order_disputes_update_ops ON public.order_disputes
  FOR UPDATE TO authenticated
  USING (public.is_platform_ops())
  WITH CHECK (public.is_platform_ops());

DROP POLICY IF EXISTS orders_select_platform_ops ON public.orders;
CREATE POLICY orders_select_platform_ops ON public.orders
  FOR SELECT TO authenticated
  USING (public.is_platform_ops());

DROP POLICY IF EXISTS users_select_platform_ops_kyc ON public.users;
CREATE POLICY users_select_platform_ops_kyc ON public.users
  FOR SELECT TO authenticated
  USING (public.is_platform_ops());

CREATE OR REPLACE FUNCTION public.create_support_ticket(
  p_subject text,
  p_body text,
  p_order_id uuid DEFAULT NULL,
  p_order_number text DEFAULT NULL,
  p_category text DEFAULT 'general',
  p_channel text DEFAULT 'in_app'
)
RETURNS public.support_tickets
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.support_tickets;
  v_public text;
  v_cat text := COALESCE(NULLIF(trim(p_category), ''), 'general');
  v_channel text := COALESCE(NULLIF(trim(p_channel), ''), 'in_app');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sign in required';
  END IF;
  IF v_cat NOT IN ('general', 'order', 'refund', 'delivery', 'account', 'quality') THEN
    v_cat := 'general';
  END IF;
  IF v_channel NOT IN ('in_app', 'email', 'whatsapp') THEN
    v_channel := 'in_app';
  END IF;

  v_public := 'TKT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  INSERT INTO public.support_tickets (
    public_id, created_by, order_id, order_number, subject, body, channel, category, sla_due_at
  ) VALUES (
    v_public,
    v_uid,
    p_order_id,
    NULLIF(trim(COALESCE(p_order_number, '')), ''),
    COALESCE(NULLIF(trim(p_subject), ''), 'HotPotChef support'),
    COALESCE(NULLIF(trim(p_body), ''), 'Need help with my order.'),
    v_channel,
    v_cat,
    now() + interval '1 day'
  )
  RETURNING * INTO v_row;

  INSERT INTO public.support_ticket_messages (ticket_id, author_id, body, is_internal)
  VALUES (v_row.id, v_uid, v_row.body, false);

  IF p_order_id IS NOT NULL AND v_cat IN ('refund', 'quality', 'delivery', 'order') THEN
    INSERT INTO public.order_disputes (
      public_id, order_id, opened_by, support_ticket_id, reason, sla_due_at
    ) VALUES (
      'DSP-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
      p_order_id,
      v_uid,
      v_row.id,
      CASE v_cat
        WHEN 'refund' THEN 'refund_failed'
        WHEN 'quality' THEN 'quality'
        WHEN 'delivery' THEN 'late'
        ELSE 'other'
      END,
      now() + interval '1 day'
    );
  END IF;

  RETURN v_row;
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
  IF NOT public.is_platform_ops() THEN
    RAISE EXCEPTION 'Platform ops only';
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
  IF NOT public.is_platform_ops() THEN
    RAISE EXCEPTION 'Platform ops only';
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

GRANT EXECUTE ON FUNCTION public.create_support_ticket(text, text, uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ops_set_ticket_status(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ops_set_dispute_status(uuid, text, text) TO authenticated;
