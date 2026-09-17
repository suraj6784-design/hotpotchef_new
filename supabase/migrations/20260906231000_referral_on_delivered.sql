-- Grant first-order referral on Delivered, not on insert.
-- Also claw back if a rewarded order later cancels/rejects (best-effort).

CREATE OR REPLACE FUNCTION public.grant_first_order_referral_bonus(p_customer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
  v_already timestamptz;
  v_order_count int;
  v_referrer_id uuid;
  v_reward numeric := 50;
BEGIN
  IF p_customer_id IS NULL THEN
    RETURN;
  END IF;

  SELECT upper(trim(referred_by)), referral_rewarded_at
    INTO v_code, v_already
  FROM public.users
  WHERE id = p_customer_id
  FOR UPDATE;

  IF v_already IS NOT NULL OR v_code IS NULL OR v_code = '' THEN
    RETURN;
  END IF;

  -- First delivered order only (pending / cancel do not grant).
  SELECT count(*) INTO v_order_count
  FROM public.orders
  WHERE customer_id = p_customer_id
    AND lower(coalesce(status, '')) LIKE '%deliver%';

  IF COALESCE(v_order_count, 0) <> 1 THEN
    RETURN;
  END IF;

  SELECT id INTO v_referrer_id
  FROM public.users
  WHERE upper(trim(referral_code)) = v_code
    AND id <> p_customer_id
  LIMIT 1;

  IF v_referrer_id IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.users
  SET referral_rewarded_at = now()
  WHERE id = p_customer_id
    AND referral_rewarded_at IS NULL;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  PERFORM set_config('app.coin_reason', 'Referral bonus — first order', true);
  UPDATE public.users
  SET hotpot_coins = COALESCE(hotpot_coins, 0) + v_reward
  WHERE id = p_customer_id;

  PERFORM set_config('app.coin_reason', 'Referral bonus — friend ordered', true);
  UPDATE public.users
  SET hotpot_coins = COALESCE(hotpot_coins, 0) + v_reward
  WHERE id = v_referrer_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.grant_referral_bonus_after_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND NEW.customer_id IS NOT NULL
     AND lower(coalesce(NEW.status, '')) LIKE '%deliver%'
     AND lower(coalesce(OLD.status, '')) NOT LIKE '%deliver%' THEN
    PERFORM public.grant_first_order_referral_bonus(NEW.customer_id);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_referral_first_order_bonus ON public.orders;
DROP TRIGGER IF EXISTS trg_grant_referral_bonus_after_order ON public.orders;
CREATE TRIGGER trg_grant_referral_bonus_after_order
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.grant_referral_bonus_after_order();

CREATE OR REPLACE FUNCTION public.clawback_referral_bonus_on_cancel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
  v_referrer uuid;
  v_rewarded_at timestamptz;
BEGIN
  IF TG_OP <> 'UPDATE' OR NEW.customer_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT (
    (lower(coalesce(NEW.status, '')) LIKE '%cancel%' OR lower(coalesce(NEW.status, '')) LIKE '%reject%')
    AND lower(coalesce(OLD.status, '')) NOT LIKE '%cancel%'
    AND lower(coalesce(OLD.status, '')) NOT LIKE '%reject%'
  ) THEN
    RETURN NEW;
  END IF;

  SELECT upper(trim(referred_by)), referral_rewarded_at
  INTO v_code, v_rewarded_at
  FROM public.users
  WHERE id = NEW.customer_id;

  IF v_code IS NULL OR v_code = '' OR v_rewarded_at IS NULL THEN
    RETURN NEW;
  END IF;

  -- Only claw back when this was still their sole non-cancel order path.
  IF (
    SELECT count(*) FROM public.orders o
    WHERE o.customer_id = NEW.customer_id
      AND lower(coalesce(o.status, '')) LIKE '%deliver%'
  ) > 0 THEN
    RETURN NEW;
  END IF;

  SELECT id INTO v_referrer
  FROM public.users
  WHERE upper(trim(referral_code)) = v_code
  LIMIT 1;

  IF v_referrer IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.users
  SET hotpot_coins = GREATEST(0, COALESCE(hotpot_coins, 0) - 50),
      referral_rewarded_at = NULL
  WHERE id = NEW.customer_id
    AND referral_rewarded_at IS NOT NULL;

  UPDATE public.users
  SET hotpot_coins = GREATEST(0, COALESCE(hotpot_coins, 0) - 50)
  WHERE id = v_referrer;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_clawback_referral_bonus_on_cancel ON public.orders;
CREATE TRIGGER trg_clawback_referral_bonus_on_cancel
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.clawback_referral_bonus_on_cancel();

NOTIFY pgrst, 'reload schema';
