-- First-order referral: both friend and referrer get 50 coins, once.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS referral_rewarded_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS users_referral_code_unique
  ON public.users (upper(trim(referral_code)))
  WHERE referral_code IS NOT NULL AND length(trim(referral_code)) > 0;

CREATE OR REPLACE FUNCTION public.record_hotpot_coin_movement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  delta numeric;
  reason text;
BEGIN
  delta := COALESCE(NEW.hotpot_coins, 0) - COALESCE(OLD.hotpot_coins, 0);
  IF delta = 0 THEN
    RETURN NEW;
  END IF;

  reason := nullif(current_setting('app.coin_reason', true), '');

  INSERT INTO public.transactions (user_id, amount, transaction_type, description)
  VALUES (
    NEW.id,
    ABS(delta),
    CASE WHEN delta > 0 THEN 'earning' ELSE 'payment' END,
    COALESCE(
      reason,
      CASE WHEN delta > 0 THEN 'HotPot Coins credited' ELSE 'Coins applied at checkout' END
    )
  );
  RETURN NEW;
END;
$$;

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

  SELECT count(*) INTO v_order_count
  FROM public.orders
  WHERE customer_id = p_customer_id;

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
  PERFORM public.grant_first_order_referral_bonus(NEW.customer_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_referral_first_order_bonus ON public.orders;
CREATE TRIGGER orders_referral_first_order_bonus
  AFTER INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.grant_referral_bonus_after_order();

REVOKE ALL ON FUNCTION public.grant_first_order_referral_bonus(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.grant_first_order_referral_bonus(uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
