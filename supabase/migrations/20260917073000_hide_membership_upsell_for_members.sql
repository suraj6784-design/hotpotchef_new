-- Never attach a sellable plan to the flash payload while a subscription is active.

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
  IF public.diner_membership_is_active(auth.uid()) THEN
    RETURN jsonb_build_object(
      'active_member', true,
      'eligible', false,
      'reason', 'already_member'
    );
  END IF;

  v_quote := public.membership_checkout_quote(auth.uid(), NULL);
  RETURN COALESCE(v_quote, jsonb_build_object('eligible', false))
    || jsonb_build_object('active_member', false);
END;
$$;

NOTIFY pgrst, 'reload schema';
