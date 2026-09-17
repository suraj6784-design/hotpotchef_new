-- Multi-chef catering quotes: kitchens bid; customer picks one, then pays.

CREATE TABLE IF NOT EXISTS public.customer_request_quotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.customer_requests (id) ON DELETE CASCADE,
  chef_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  chef_name text,
  quoted_total numeric NOT NULL CHECK (quoted_total > 0),
  note text,
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'selected', 'rejected', 'withdrawn')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (request_id, chef_id)
);

CREATE INDEX IF NOT EXISTS customer_request_quotes_request_idx
  ON public.customer_request_quotes (request_id, status, quoted_total);

CREATE INDEX IF NOT EXISTS customer_request_quotes_chef_idx
  ON public.customer_request_quotes (chef_id, updated_at DESC);

ALTER TABLE public.customer_request_quotes ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON public.customer_request_quotes TO authenticated;
GRANT ALL ON public.customer_request_quotes TO service_role;

DROP POLICY IF EXISTS customer_request_quotes_select ON public.customer_request_quotes;
CREATE POLICY customer_request_quotes_select ON public.customer_request_quotes
  FOR SELECT
  TO authenticated
  USING (
    chef_id = auth.uid()
    OR EXISTS (
      SELECT 1
      FROM public.customer_requests r
      WHERE r.id = request_id
        AND r.customer_id::text = auth.uid()::text
    )
  );

DROP POLICY IF EXISTS customer_request_quotes_insert ON public.customer_request_quotes;
CREATE POLICY customer_request_quotes_insert ON public.customer_request_quotes
  FOR INSERT
  TO authenticated
  WITH CHECK (chef_id = auth.uid());

DROP POLICY IF EXISTS customer_request_quotes_update ON public.customer_request_quotes;
CREATE POLICY customer_request_quotes_update ON public.customer_request_quotes
  FOR UPDATE
  TO authenticated
  USING (chef_id = auth.uid())
  WITH CHECK (chef_id = auth.uid());

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.customer_request_quotes;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;

-- Chef submits / updates a bid. Does NOT lock the lead.
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
BEGIN
  IF auth.uid() IS NULL OR NOT public.account_has_role(ARRAY['chef', 'cook']) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;
  IF p_quoted_total IS NULL OR p_quoted_total <= 0 THEN
    RAISE EXCEPTION 'invalid_quote';
  END IF;

  SELECT lower(COALESCE(status::text, ''))
  INTO v_status
  FROM public.customer_requests
  WHERE id = p_request_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;
  IF v_status <> 'open' THEN
    RAISE EXCEPTION 'request_not_open';
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

-- Customer picks one quote → locks accepted chef + quoted_total for checkout.
CREATE OR REPLACE FUNCTION public.select_customer_request_quote(p_quote_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request_id uuid;
  v_chef_id uuid;
  v_chef_name text;
  v_total numeric;
  v_customer_id text;
  v_status text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  SELECT
    q.request_id,
    q.chef_id,
    q.chef_name,
    q.quoted_total,
    r.customer_id::text,
    lower(COALESCE(r.status::text, ''))
  INTO
    v_request_id,
    v_chef_id,
    v_chef_name,
    v_total,
    v_customer_id,
    v_status
  FROM public.customer_request_quotes q
  JOIN public.customer_requests r ON r.id = q.request_id
  WHERE q.id = p_quote_id
    AND q.status IN ('open', 'selected');

  IF v_request_id IS NULL THEN
    RETURN false;
  END IF;
  IF v_customer_id IS DISTINCT FROM auth.uid()::text THEN
    RETURN false;
  END IF;
  -- Open = still collecting bids; Accepted = unpaid pick (customer may switch).
  IF v_status NOT IN ('open', 'accepted') THEN
    RETURN false;
  END IF;

  UPDATE public.customer_request_quotes
  SET status = 'open', updated_at = now()
  WHERE request_id = v_request_id
    AND id <> p_quote_id
    AND status = 'selected';

  UPDATE public.customer_request_quotes
  SET status = 'selected', updated_at = now()
  WHERE id = p_quote_id;

  UPDATE public.customer_requests
  SET
    status = 'Accepted',
    accepted_chef_id = v_chef_id,
    accepted_chef_name = COALESCE(NULLIF(btrim(COALESCE(v_chef_name, '')), ''), accepted_chef_name),
    quoted_total = v_total,
    remaining_quantity = 0
  WHERE id = v_request_id;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.select_customer_request_quote(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.select_customer_request_quote(uuid) TO authenticated, service_role;

-- Keep exclusive claim for packaging / legacy callers, but catering UI uses quotes.
NOTIFY pgrst, 'reload schema';
