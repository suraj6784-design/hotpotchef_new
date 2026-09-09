-- Silver Foodie keeps the badge; packaging stays ₹20 like Bronze. Gold remains free.

CREATE OR REPLACE FUNCTION public.packaging_fee_for_loyalty(p_user_id uuid)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_tier text;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN 20;
  END IF;

  SELECT loyalty_tier INTO v_tier
  FROM public.user_gamification
  WHERE user_id = p_user_id;

  IF lower(COALESCE(v_tier, '')) LIKE '%gold%' THEN
    RETURN 0;
  END IF;
  RETURN 20;
END;
$$;

NOTIFY pgrst, 'reload schema';
