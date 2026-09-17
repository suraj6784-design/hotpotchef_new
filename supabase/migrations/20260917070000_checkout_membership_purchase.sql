-- Pay membership on the food order, grant Family member immediately.

ALTER TABLE public.membership_plans
  ADD COLUMN IF NOT EXISTS member_title text NOT NULL DEFAULT 'Family member';

ALTER TABLE public.pending_checkouts
  ADD COLUMN IF NOT EXISTS membership_plan_id uuid,
  ADD COLUMN IF NOT EXISTS membership_fee numeric NOT NULL DEFAULT 0;

UPDATE public.membership_plans
SET member_title = 'Family member'
WHERE member_title IS NULL OR btrim(member_title) = '';

CREATE OR REPLACE FUNCTION public.membership_checkout_quote(p_user_id uuid, p_plan_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan public.membership_plans%ROWTYPE;
  v_flash boolean;
  v_price numeric;
BEGIN
  IF p_user_id IS NOT NULL AND public.diner_membership_is_active(p_user_id) THEN
    RETURN jsonb_build_object('eligible', false, 'reason', 'already_member');
  END IF;

  IF p_plan_id IS NOT NULL THEN
    SELECT * INTO v_plan FROM public.membership_plans WHERE id = p_plan_id AND is_active;
  END IF;
  IF v_plan.id IS NULL THEN
    SELECT * INTO v_plan
    FROM public.membership_plans
    WHERE is_active
      AND flash_enabled
      AND (flash_starts_at IS NULL OR flash_starts_at <= now())
      AND (flash_ends_at IS NULL OR flash_ends_at >= now())
    ORDER BY sort_order, offer_price_inr
    LIMIT 1;
  END IF;
  IF v_plan.id IS NULL THEN
    SELECT * INTO v_plan FROM public.membership_plans WHERE is_active ORDER BY sort_order LIMIT 1;
  END IF;
  IF v_plan.id IS NULL THEN
    RETURN jsonb_build_object('eligible', false, 'reason', 'no_plan');
  END IF;

  v_flash := v_plan.flash_enabled
    AND (v_plan.flash_starts_at IS NULL OR v_plan.flash_starts_at <= now())
    AND (v_plan.flash_ends_at IS NULL OR v_plan.flash_ends_at >= now());
  v_price := CASE WHEN v_flash THEN v_plan.offer_price_inr ELSE v_plan.list_price_inr END;

  RETURN jsonb_build_object(
    'eligible', true,
    'plan_id', v_plan.id,
    'name', v_plan.name,
    'member_title', COALESCE(NULLIF(btrim(v_plan.member_title), ''), 'Family member'),
    'list_price_inr', v_plan.list_price_inr,
    'offer_price_inr', v_price,
    'duration_days', v_plan.duration_days,
    'flash_enabled', v_flash,
    'flash_label', COALESCE(v_plan.flash_label, '')
  );
END;
$$;

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

  INSERT INTO public.diner_memberships (
    user_id, plan_id, starts_at, ends_at, status, amount_paid, note
  ) VALUES (
    NEW.customer_id,
    v_plan,
    now(),
    now() + make_interval(days => v_days),
    'active',
    GREATEST(0, v_fee),
    'Paid with order · ' || v_title
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'membership grant failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_grant_membership ON public.orders;
CREATE TRIGGER orders_grant_membership
AFTER INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.grant_membership_for_paid_order();

CREATE OR REPLACE FUNCTION public.diner_flash_membership_offer()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_quote jsonb;
BEGIN
  v_quote := public.membership_checkout_quote(auth.uid(), NULL);
  RETURN v_quote || jsonb_build_object(
    'active_member', public.diner_membership_is_active(auth.uid())
  );
END;
$$;

REVOKE ALL ON FUNCTION public.membership_checkout_quote(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.membership_checkout_quote(uuid, uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.diner_flash_membership_offer() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.diner_flash_membership_offer() TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
