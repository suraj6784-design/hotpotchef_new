-- Diners can invite specific kitchens on a bulk catering broadcast.
-- Empty / null target_chef_ids keeps the existing "all nearby chefs" behaviour.

DO $$
BEGIN
  IF to_regclass('public.customer_requests') IS NULL THEN
    RAISE NOTICE 'customer_requests missing; skip target_chef_ids';
    RETURN;
  END IF;

  ALTER TABLE public.customer_requests
    ADD COLUMN IF NOT EXISTS target_chef_ids uuid[] NOT NULL DEFAULT '{}'::uuid[];

  CREATE INDEX IF NOT EXISTS customer_requests_target_chefs_gin
    ON public.customer_requests
    USING gin (target_chef_ids);

  DROP POLICY IF EXISTS customer_requests_select ON public.customer_requests;
  CREATE POLICY customer_requests_select ON public.customer_requests
    FOR SELECT
    TO authenticated
    USING (
      public.is_platform_ops()
      OR customer_id::text = auth.uid()::text
      OR accepted_chef_id::text = auth.uid()::text
      OR (
        lower(coalesce(status::text, '')) = 'open'
        AND lower(coalesce(service_type::text, '')) <> 'packaging'
        AND lower(coalesce(request_type::text, '')) NOT IN ('packaging', 'supply')
        AND coalesce(description, '') !~* '\ySUP-[A-Z0-9]+\y'
        AND (
          cardinality(coalesce(target_chef_ids, '{}'::uuid[])) = 0
          OR auth.uid() = ANY (target_chef_ids)
        )
      )
    );

  DROP POLICY IF EXISTS customer_requests_update ON public.customer_requests;
  CREATE POLICY customer_requests_update ON public.customer_requests
    FOR UPDATE
    TO authenticated
    USING (
      customer_id::text = auth.uid()::text
      OR accepted_chef_id::text = auth.uid()::text
      OR (
        lower(coalesce(status::text, '')) = 'open'
        AND public.account_has_role(ARRAY['chef', 'cook'])
        AND (
          cardinality(coalesce(target_chef_ids, '{}'::uuid[])) = 0
          OR auth.uid() = ANY (target_chef_ids)
        )
      )
    )
    WITH CHECK (
      customer_id::text = auth.uid()::text
      OR accepted_chef_id::text = auth.uid()::text
    );
END $$;

DO $$
BEGIN
  IF to_regclass('public.customer_request_quotes') IS NULL THEN
    RETURN;
  END IF;

  DROP POLICY IF EXISTS customer_request_quotes_insert ON public.customer_request_quotes;
  CREATE POLICY customer_request_quotes_insert ON public.customer_request_quotes
    FOR INSERT
    TO authenticated
    WITH CHECK (
      chef_id = auth.uid()
      AND EXISTS (
        SELECT 1
        FROM public.customer_requests r
        WHERE r.id = request_id
          AND lower(coalesce(r.status::text, '')) = 'open'
          AND (
            cardinality(coalesce(r.target_chef_ids, '{}'::uuid[])) = 0
            OR auth.uid() = ANY (r.target_chef_ids)
          )
      )
    );
END $$;

CREATE OR REPLACE FUNCTION public.submit_customer_request_quote(
  p_request_id uuid,
  p_quoted_total numeric,
  p_chef_name text DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_status text;
  v_targets uuid[];
BEGIN
  IF auth.uid() IS NULL OR NOT public.account_has_role(ARRAY['chef', 'cook']) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;
  IF p_quoted_total IS NULL OR p_quoted_total <= 0 THEN
    RAISE EXCEPTION 'invalid_quote';
  END IF;

  SELECT lower(COALESCE(status::text, '')), target_chef_ids
  INTO v_status, v_targets
  FROM public.customer_requests
  WHERE id = p_request_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;
  IF v_status <> 'open' THEN
    RAISE EXCEPTION 'request_not_open';
  END IF;
  IF v_targets IS NOT NULL
     AND cardinality(v_targets) > 0
     AND NOT (auth.uid() = ANY (v_targets)) THEN
    RAISE EXCEPTION 'not_invited';
  END IF;

  INSERT INTO public.customer_request_quotes (
    request_id,
    chef_id,
    chef_name,
    quoted_total,
    note,
    status,
    updated_at
  )
  VALUES (
    p_request_id,
    auth.uid(),
    NULLIF(btrim(COALESCE(p_chef_name, '')), ''),
    p_quoted_total,
    NULLIF(btrim(COALESCE(p_note, '')), ''),
    'open',
    now()
  )
  ON CONFLICT (request_id, chef_id) DO UPDATE
  SET
    chef_name = COALESCE(
      NULLIF(btrim(COALESCE(EXCLUDED.chef_name, '')), ''),
      public.customer_request_quotes.chef_name
    ),
    quoted_total = EXCLUDED.quoted_total,
    note = COALESCE(EXCLUDED.note, public.customer_request_quotes.note),
    status = 'open',
    updated_at = now()
  WHERE public.customer_request_quotes.status IN ('open', 'withdrawn', 'rejected')
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'quote_locked';
  END IF;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_customer_request_quote(uuid, numeric, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_customer_request_quote(uuid, numeric, text, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
