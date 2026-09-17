-- Daily streak used UTC CURRENT_DATE, so IST mornings looked "already claimed".
-- Credit users.hotpot_coins and write a ledger row so Account history matches.

CREATE UNIQUE INDEX IF NOT EXISTS user_gamification_user_id_key
  ON public.user_gamification (user_id);

CREATE OR REPLACE FUNCTION public.claim_daily_streak(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_today date;
  v_streak int;
  v_last_date date;
  v_reward numeric := 15;
  v_updated int;
  v_delivered int;
BEGIN
  v_user_id := COALESCE(auth.uid(), p_user_id);
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Please sign in to claim.');
  END IF;

  v_today := (timezone('Asia/Kolkata', now()))::date;

  SELECT current_streak, last_check_in_date
  INTO v_streak, v_last_date
  FROM public.user_gamification
  WHERE user_id = v_user_id;

  IF FOUND AND v_last_date = v_today THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Already claimed today. Coins stay in your wallet until you spend them at checkout.'
    );
  END IF;

  IF FOUND AND v_last_date = v_today - 1 THEN
    v_streak := COALESCE(v_streak, 0) + 1;
  ELSE
    v_streak := 1;
  END IF;

  INSERT INTO public.user_gamification (user_id, current_streak, last_check_in_date, updated_at)
  VALUES (v_user_id, v_streak, v_today, now())
  ON CONFLICT (user_id) DO UPDATE
  SET
    current_streak = EXCLUDED.current_streak,
    last_check_in_date = EXCLUDED.last_check_in_date,
    updated_at = now();

  UPDATE public.users
  SET hotpot_coins = COALESCE(hotpot_coins, 0) + v_reward
  WHERE id = v_user_id;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN jsonb_build_object('success', false, 'message', 'Could not add HotPot Coins. Try again.');
  END IF;

  BEGIN
    INSERT INTO public.transactions (user_id, amount, transaction_type, description)
    VALUES (v_user_id, v_reward, 'earning', 'Daily streak bonus');
  EXCEPTION
    WHEN undefined_table THEN NULL;
    WHEN OTHERS THEN NULL;
  END;

  SELECT COUNT(*)::int
  INTO v_delivered
  FROM public.orders
  WHERE customer_id = v_user_id
    AND (status ILIKE '%delivered%' OR status ILIKE '%completed%');

  UPDATE public.user_gamification
  SET
    total_orders_completed = v_delivered,
    loyalty_tier = CASE
      WHEN v_delivered >= 25 THEN 'Gold Foodie'
      WHEN v_delivered >= 10 THEN 'Silver Foodie'
      ELSE 'Bronze Foodie'
    END
  WHERE user_id = v_user_id;

  RETURN jsonb_build_object('success', true, 'streak', v_streak, 'reward', v_reward);
END;
$$;

REVOKE ALL ON FUNCTION public.claim_daily_streak(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_daily_streak(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
