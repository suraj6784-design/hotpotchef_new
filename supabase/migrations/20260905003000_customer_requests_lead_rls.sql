-- Keep open catering broadcasts visible to kitchens, and keep claimed / paid
-- jobs visible to the customer and the chef who accepted them.

DO $$
BEGIN
  IF to_regclass('public.customer_requests') IS NULL THEN
    RAISE NOTICE 'customer_requests missing; skip lead RLS';
    RETURN;
  END IF;

  ALTER TABLE public.customer_requests
    ADD COLUMN IF NOT EXISTS accepted_chef_id uuid;
  ALTER TABLE public.customer_requests
    ADD COLUMN IF NOT EXISTS accepted_chef_name text;

  ALTER TABLE public.customer_requests ENABLE ROW LEVEL SECURITY;

  GRANT SELECT, INSERT, UPDATE ON public.customer_requests TO authenticated;
  GRANT ALL ON public.customer_requests TO service_role;

  DROP POLICY IF EXISTS customer_requests_select ON public.customer_requests;
  CREATE POLICY customer_requests_select ON public.customer_requests
    FOR SELECT
    TO authenticated
    USING (
      lower(coalesce(status::text, '')) = 'open'
      OR customer_id::text = auth.uid()::text
      OR accepted_chef_id::text = auth.uid()::text
    );

  DROP POLICY IF EXISTS customer_requests_insert ON public.customer_requests;
  CREATE POLICY customer_requests_insert ON public.customer_requests
    FOR INSERT
    TO authenticated
    WITH CHECK (customer_id::text = auth.uid()::text);

  DROP POLICY IF EXISTS customer_requests_update ON public.customer_requests;
  CREATE POLICY customer_requests_update ON public.customer_requests
    FOR UPDATE
    TO authenticated
    USING (
      customer_id::text = auth.uid()::text
      OR accepted_chef_id::text = auth.uid()::text
      OR lower(coalesce(status::text, '')) = 'open'
    )
    WITH CHECK (
      customer_id::text = auth.uid()::text
      OR accepted_chef_id::text = auth.uid()::text
    );
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.customer_requests;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN undefined_table THEN NULL;
END $$;

NOTIFY pgrst, 'reload schema';
