-- Wallet history was empty: transaction_type only allowed earning/refund/payout/payment,
-- while streak/checkout wrote credit/debit. RLS also blocked customer reads.

ALTER TABLE public.transactions DROP CONSTRAINT IF EXISTS transactions_transaction_type_check;
ALTER TABLE public.transactions
  ADD CONSTRAINT transactions_transaction_type_check
  CHECK (transaction_type = ANY (ARRAY[
    'earning', 'refund', 'payout', 'payment', 'credit', 'debit', 'redeem'
  ]));

ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.transactions TO authenticated;

DROP POLICY IF EXISTS transactions_select ON public.transactions;
CREATE POLICY transactions_select ON public.transactions
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- Record every users.hotpot_coins change so checkout and streak both show in history.
CREATE OR REPLACE FUNCTION public.record_hotpot_coin_movement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  delta numeric;
BEGIN
  delta := COALESCE(NEW.hotpot_coins, 0) - COALESCE(OLD.hotpot_coins, 0);
  IF delta = 0 THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.transactions (user_id, amount, transaction_type, description)
  VALUES (
    NEW.id,
    ABS(delta),
    CASE WHEN delta > 0 THEN 'earning' ELSE 'payment' END,
    CASE WHEN delta > 0 THEN 'HotPot Coins credited' ELSE 'Coins applied at checkout' END
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_hotpot_coins_ledger ON public.users;
CREATE TRIGGER users_hotpot_coins_ledger
  AFTER UPDATE OF hotpot_coins ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.record_hotpot_coin_movement();

-- Reconstruct spends from orders that already applied coins.
INSERT INTO public.transactions (user_id, amount, transaction_type, description, created_at)
SELECT o.customer_id, o.coins_applied, 'payment', 'Coins applied at checkout', o.created_at
FROM public.orders o
WHERE o.customer_id IS NOT NULL
  AND COALESCE(o.coins_applied, 0) > 0
  AND NOT EXISTS (
    SELECT 1
    FROM public.transactions t
    WHERE t.user_id = o.customer_id
      AND t.transaction_type = 'payment'
      AND t.created_at = o.created_at
  );

-- Reconstruct streak credits from the recorded streak length (15 coins per check-in day).
INSERT INTO public.transactions (user_id, amount, transaction_type, description, created_at)
SELECT
  g.user_id,
  15,
  'earning',
  'Daily streak bonus',
  ((g.last_check_in_date - (s.n || ' days')::interval) + time '12:00') AT TIME ZONE 'Asia/Kolkata'
FROM public.user_gamification g
CROSS JOIN LATERAL generate_series(0, GREATEST(COALESCE(g.current_streak, 0), 1) - 1) AS s(n)
WHERE g.last_check_in_date IS NOT NULL
  AND COALESCE(g.current_streak, 0) > 0
  AND NOT EXISTS (
    SELECT 1
    FROM public.transactions t
    WHERE t.user_id = g.user_id
      AND t.description = 'Daily streak bonus'
      AND (t.created_at AT TIME ZONE 'Asia/Kolkata')::date = (g.last_check_in_date - s.n)
  );

NOTIFY pgrst, 'reload schema';
