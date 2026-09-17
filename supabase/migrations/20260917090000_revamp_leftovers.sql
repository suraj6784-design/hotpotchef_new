-- Membership cancel, GST on the plan, membership-only grant, driver weekly payout window.

ALTER TABLE public.diner_memberships
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS gst_inr numeric NOT NULL DEFAULT 0;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS membership_fee numeric NOT NULL DEFAULT 0;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS razorpay_customer_id text,
  ADD COLUMN IF NOT EXISTS preferred_locale text;

CREATE OR REPLACE FUNCTION public.grant_membership_for_paid_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan uuid;
  v_fee numeric := 0;
  v_days integer := 90;
  v_title text := 'Family member';
  v_gst numeric := 0;
BEGIN
  IF NEW.razorpay_order_id IS NULL OR btrim(NEW.razorpay_order_id) = '' THEN
    RETURN NEW;
  END IF;
  IF public.diner_membership_is_active(NEW.customer_id) THEN
    RETURN NEW;
  END IF;

  SELECT membership_plan_id, COALESCE(membership_fee, 0)
    INTO v_plan, v_fee
    FROM public.pending_checkouts
   WHERE razorpay_order_id = NEW.razorpay_order_id;

  IF v_plan IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT GREATEST(1, COALESCE(duration_days, 90)),
         COALESCE(NULLIF(btrim(member_title), ''), 'Family member')
    INTO v_days, v_title
    FROM public.membership_plans
   WHERE id = v_plan;

  v_gst := ROUND(GREATEST(0, v_fee) - (GREATEST(0, v_fee) / 1.18), 2);

  INSERT INTO public.diner_memberships (
    user_id, plan_id, starts_at, ends_at, status, amount_paid, gst_inr, note
  ) VALUES (
    NEW.customer_id,
    v_plan,
    now(),
    now() + make_interval(days => v_days),
    'active',
    GREATEST(0, v_fee),
    GREATEST(0, v_gst),
    'Paid with order · ' || v_title
  );

  IF v_fee > 0 AND COALESCE(NEW.membership_fee, 0) = 0 THEN
    UPDATE public.orders
       SET membership_fee = v_fee,
           total_price = COALESCE(total_price, 0) + v_fee
     WHERE id = NEW.id;
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'membership grant failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.diner_cancel_membership()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Sign in required');
  END IF;

  UPDATE public.diner_memberships
  SET status = 'cancelled',
      cancelled_at = now(),
      ends_at = now()
  WHERE user_id = auth.uid()
    AND status = 'active'
    AND ends_at > now()
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'No active Family member plan');
  END IF;
  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.diner_cancel_membership() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.diner_cancel_membership() TO authenticated;

CREATE OR REPLACE FUNCTION public.grant_paid_membership(
  p_user_id uuid,
  p_plan_id uuid,
  p_amount numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days int;
  v_title text;
  v_gst numeric;
BEGIN
  IF p_user_id IS NULL OR p_plan_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Missing plan');
  END IF;
  IF public.diner_membership_is_active(p_user_id) THEN
    RETURN jsonb_build_object('success', true, 'already_member', true);
  END IF;

  SELECT GREATEST(1, COALESCE(duration_days, 90)),
         COALESCE(NULLIF(btrim(member_title), ''), 'Family member')
    INTO v_days, v_title
  FROM public.membership_plans
  WHERE id = p_plan_id;
  IF v_days IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unknown plan');
  END IF;

  v_gst := ROUND(GREATEST(0, COALESCE(p_amount, 0)) - (GREATEST(0, COALESCE(p_amount, 0)) / 1.18), 2);

  INSERT INTO public.diner_memberships (
    user_id, plan_id, starts_at, ends_at, status, amount_paid, gst_inr, note
  ) VALUES (
    p_user_id,
    p_plan_id,
    now(),
    now() + make_interval(days => v_days),
    'active',
    GREATEST(0, COALESCE(p_amount, 0)),
    GREATEST(0, v_gst),
    'Paid Family member · ' || v_title
  );
  RETURN jsonb_build_object('success', true, 'gst_inr', v_gst);
END;
$$;

REVOKE ALL ON FUNCTION public.grant_paid_membership(uuid, uuid, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.grant_paid_membership(uuid, uuid, numeric) TO service_role;

CREATE OR REPLACE FUNCTION public.driver_payout_cadence(p_driver_id uuid DEFAULT auth.uid())
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pending numeric := 0;
  v_next date;
  v_driver uuid;
BEGIN
  v_driver := COALESCE(auth.uid(), p_driver_id);
  IF v_driver IS NULL THEN
    RETURN jsonb_build_object('success', false);
  END IF;
  SELECT COALESCE(wallet_balance, 0) INTO v_pending
  FROM public.driver_profiles
  WHERE user_id = v_driver;

  v_next := (timezone('Asia/Kolkata', now()))::date;
  -- Next Monday in IST (ISO DOW: 1 = Monday).
  v_next := v_next + ((8 - EXTRACT(ISODOW FROM v_next)::int) % 7);
  IF EXTRACT(ISODOW FROM (timezone('Asia/Kolkata', now()))::date)::int = 1
     AND EXTRACT(HOUR FROM timezone('Asia/Kolkata', now())) < 10 THEN
    v_next := (timezone('Asia/Kolkata', now()))::date;
  ELSIF EXTRACT(ISODOW FROM (timezone('Asia/Kolkata', now()))::date)::int = 1 THEN
    v_next := v_next + 7;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'pending_inr', COALESCE(v_pending, 0),
    'next_payout_date', v_next,
    'cadence', 'Weekly bank transfer every Monday after KYC, arranged by ops from this wallet.'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.driver_payout_cadence(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_payout_cadence(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
