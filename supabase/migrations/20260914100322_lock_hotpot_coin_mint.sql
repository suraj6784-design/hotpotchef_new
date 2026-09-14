-- Wallet mint was a public SECURITY DEFINER RPC with no auth.uid check.
-- Clients can also PATCH users.hotpot_coins via "manage own profile".
-- Credits stay in claim_daily_streak / referral / place_customer_order (DEFINER).

CREATE OR REPLACE FUNCTION public.add_hotpot_coins(customer_uuid uuid, coins_to_add numeric)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Coins can only be credited by the payment service';
  END IF;
  IF customer_uuid IS NULL OR coins_to_add IS NULL OR coins_to_add <= 0 THEN
    RAISE EXCEPTION 'Invalid coin credit';
  END IF;

  UPDATE public.users
  SET hotpot_coins = COALESCE(hotpot_coins, 0) + coins_to_add
  WHERE id = customer_uuid;
END;
$$;

REVOKE ALL ON FUNCTION public.add_hotpot_coins(uuid, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.add_hotpot_coins(uuid, numeric) TO service_role;

CREATE OR REPLACE FUNCTION public.prevent_client_hotpot_coin_edits()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF current_user IN ('anon', 'authenticated')
     AND NEW.hotpot_coins IS DISTINCT FROM OLD.hotpot_coins THEN
    RAISE EXCEPTION 'HotPot Coins cannot be changed from the app';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_prevent_client_hotpot_coin_edits ON public.users;
CREATE TRIGGER users_prevent_client_hotpot_coin_edits
  BEFORE UPDATE OF hotpot_coins ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_client_hotpot_coin_edits();
