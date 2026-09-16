-- Wallet showed two streak / credited / checkout lines because the coins
-- trigger and explicit INSERTs both wrote. Debits stay on place_order;
-- credits use the trigger (with app.coin_reason). Attach order_id when we can.

ALTER TABLE public.transactions
  ADD COLUMN IF NOT EXISTS order_id uuid REFERENCES public.orders (id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS transactions_user_created_idx
  ON public.transactions (user_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.record_hotpot_coin_movement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  delta numeric;
  reason text;
  skip text;
  order_ref uuid;
BEGIN
  delta := COALESCE(NEW.hotpot_coins, 0) - COALESCE(OLD.hotpot_coins, 0);
  IF delta = 0 THEN
    RETURN NEW;
  END IF;

  -- Checkout writes its own debit row after this UPDATE.
  IF delta < 0 THEN
    RETURN NEW;
  END IF;

  skip := nullif(current_setting('app.coin_skip', true), '');
  IF skip = '1' THEN
    RETURN NEW;
  END IF;

  reason := nullif(current_setting('app.coin_reason', true), '');
  BEGIN
    order_ref := nullif(current_setting('app.coin_order_id', true), '')::uuid;
  EXCEPTION WHEN OTHERS THEN
    order_ref := NULL;
  END;

  IF EXISTS (
    SELECT 1
    FROM public.transactions t
    WHERE t.user_id = NEW.id
      AND abs(t.amount) = abs(delta)
      AND t.created_at > now() - interval '2 minutes'
  ) THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.transactions (user_id, amount, transaction_type, description, order_id)
  VALUES (
    NEW.id,
    abs(delta),
    'earning',
    COALESCE(reason, 'HotPot Coins credited'),
    order_ref
  );
  RETURN NEW;
END;
$$;

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

  PERFORM set_config('app.coin_reason', 'Daily streak bonus', true);
  UPDATE public.users
  SET hotpot_coins = COALESCE(hotpot_coins, 0) + v_reward
  WHERE id = v_user_id;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN jsonb_build_object('success', false, 'message', 'Could not add HotPot Coins. Try again.');
  END IF;

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

-- Collapse already-duplicated wallet lines (same family, amount, minute).
DELETE FROM public.transactions a
USING public.transactions b
WHERE a.ctid < b.ctid
  AND a.user_id = b.user_id
  AND abs(a.amount) = abs(b.amount)
  AND date_trunc('minute', a.created_at) = date_trunc('minute', b.created_at)
  AND (
    (a.description ILIKE '%streak%' AND b.description ILIKE '%streak%')
    OR (a.description ILIKE '%checkout%' AND b.description ILIKE '%checkout%')
    OR (a.description ILIKE '%credited%' AND b.description ILIKE '%credited%')
    OR (a.description ILIKE '%restored%' AND b.description ILIKE '%restored%')
  );

UPDATE public.transactions t
SET order_id = matched.order_id
FROM (
  SELECT DISTINCT ON (t.id)
    t.id AS txn_id,
    o.id AS order_id
  FROM public.transactions t
  JOIN public.orders o ON o.customer_id = t.user_id
  WHERE t.order_id IS NULL
    AND t.description NOT ILIKE '%streak%'
    AND t.description NOT ILIKE '%referral%'
    AND abs(extract(epoch FROM (t.created_at - o.created_at))) < 86400
  ORDER BY
    t.id,
    CASE WHEN coalesce(o.coins_applied, 0) = abs(t.amount) THEN 0 ELSE 1 END,
    abs(extract(epoch FROM (t.created_at - o.created_at)))
) matched
WHERE t.id = matched.txn_id
  AND (
    t.description ILIKE '%checkout%'
    OR t.description ILIKE '%credited%'
    OR t.description ILIKE '%restored%'
    OR t.transaction_type IN ('payment', 'debit', 'redeem', 'refund')
  );

NOTIFY pgrst, 'reload schema';
