-- Close leftover open bids when a catering request is paid/ordered.

CREATE OR REPLACE FUNCTION public.finalize_customer_request_quotes(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer text;
  v_status text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN;
  END IF;

  SELECT customer_id::text, lower(COALESCE(status::text, ''))
  INTO v_customer, v_status
  FROM public.customer_requests
  WHERE id = p_request_id;

  IF v_customer IS NULL OR v_customer IS DISTINCT FROM auth.uid()::text THEN
    RETURN;
  END IF;
  IF v_status NOT IN ('ordered', 'paid', 'accepted') THEN
    RETURN;
  END IF;

  UPDATE public.customer_request_quotes
  SET status = 'rejected', updated_at = now()
  WHERE request_id = p_request_id
    AND status = 'open';
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_customer_request_quotes(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.finalize_customer_request_quotes(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
