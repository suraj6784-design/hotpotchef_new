-- P0: platform ops membership, packaging inbox, FSSAI verification, lock live signals.

-- ---------------------------------------------------------------------------
-- Platform ops allowlist (in-app Packaging + FSSAI desks)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.platform_ops (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.platform_ops ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.platform_ops TO authenticated;
GRANT ALL ON public.platform_ops TO service_role;

DROP POLICY IF EXISTS platform_ops_select_self ON public.platform_ops;
CREATE POLICY platform_ops_select_self ON public.platform_ops
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.is_platform_ops()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.platform_ops
    WHERE user_id = auth.uid()
  )
  OR lower(coalesce(auth.jwt() -> 'user_metadata' ->> 'role', '')) = 'ops'
  OR lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) = 'ops';
$$;

REVOKE ALL ON FUNCTION public.is_platform_ops() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_platform_ops() TO authenticated, service_role;

COMMENT ON TABLE public.platform_ops IS
  'Users who may operate Packaging inbox and FSSAI verification in-app. Seed with INSERT … user_id.';

-- ---------------------------------------------------------------------------
-- Packaging supply request status + ops update RPC
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.customer_requests') IS NULL THEN
    RAISE NOTICE 'customer_requests missing; skip packaging ops columns';
    RETURN;
  END IF;

  ALTER TABLE public.customer_requests
    ADD COLUMN IF NOT EXISTS ops_note text,
    ADD COLUMN IF NOT EXISTS ops_updated_at timestamptz,
    ADD COLUMN IF NOT EXISTS ops_updated_by uuid,
    ADD COLUMN IF NOT EXISTS request_type text;

  -- Tighten SELECT: packaging rows are owner + ops only; catering Open stays kitchen-visible.
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
      )
    );
END $$;

CREATE OR REPLACE FUNCTION public.ops_set_packaging_request_status(
  p_request_id uuid,
  p_status text,
  p_ops_note text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text := trim(p_status);
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_ops() THEN
    RAISE EXCEPTION 'Platform ops membership required';
  END IF;

  IF lower(v_status) NOT IN (
    'open', 'confirmed', 'packed', 'out for delivery', 'fulfilled', 'rejected', 'cancelled'
  ) THEN
    RAISE EXCEPTION 'Invalid packaging status';
  END IF;

  -- Canonical casing for app detectors.
  v_status := CASE lower(v_status)
    WHEN 'open' THEN 'Open'
    WHEN 'confirmed' THEN 'Confirmed'
    WHEN 'packed' THEN 'Packed'
    WHEN 'out for delivery' THEN 'Out for Delivery'
    WHEN 'fulfilled' THEN 'Fulfilled'
    WHEN 'rejected' THEN 'Rejected'
    WHEN 'cancelled' THEN 'Cancelled'
    ELSE v_status
  END;

  UPDATE public.customer_requests
  SET
    status = v_status,
    ops_note = COALESCE(p_ops_note, ops_note),
    ops_updated_at = now(),
    ops_updated_by = auth.uid()
  WHERE id = p_request_id
    AND (
      lower(coalesce(service_type, '')) = 'packaging'
      OR lower(coalesce(request_type, '')) IN ('packaging', 'supply')
      OR coalesce(description, '') ~* 'SUP-[A-Z0-9]+'
    );

  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.ops_set_packaging_request_status(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ops_set_packaging_request_status(uuid, text, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- FSSAI proof + verification
-- ---------------------------------------------------------------------------
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS fssai_number text,
  ADD COLUMN IF NOT EXISTS fssai_proof_url text,
  ADD COLUMN IF NOT EXISTS fssai_verification_status text NOT NULL DEFAULT 'unsubmitted',
  ADD COLUMN IF NOT EXISTS fssai_review_note text,
  ADD COLUMN IF NOT EXISTS fssai_verified_at timestamptz,
  ADD COLUMN IF NOT EXISTS fssai_reviewed_by uuid;

DO $$
DECLARE
  cname text;
BEGIN
  SELECT con.conname INTO cname
  FROM pg_constraint con
  JOIN pg_class rel ON rel.oid = con.conrelid
  JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
  WHERE nsp.nspname = 'public'
    AND rel.relname = 'users'
    AND con.contype = 'c'
    AND pg_get_constraintdef(con.oid) ILIKE '%fssai_verification_status%'
  ORDER BY con.conname
  FETCH FIRST 1 ROW ONLY;
  IF cname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.users DROP CONSTRAINT %I', cname);
  END IF;
END $$;

ALTER TABLE public.users
  DROP CONSTRAINT IF EXISTS users_fssai_verification_status_check;
ALTER TABLE public.users
  ADD CONSTRAINT users_fssai_verification_status_check
  CHECK (fssai_verification_status IN ('unsubmitted', 'pending', 'verified', 'rejected'));

COMMENT ON COLUMN public.users.fssai_proof_url IS
  'Photo/scan of FSSAI licence uploaded by the chef for ops review.';
COMMENT ON COLUMN public.users.fssai_verification_status IS
  'unsubmitted | pending | verified | rejected — publish requires pending or verified with proof.';

CREATE OR REPLACE FUNCTION public.ops_set_fssai_status(
  p_chef_id uuid,
  p_status text,
  p_review_note text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text := lower(trim(p_status));
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_ops() THEN
    RAISE EXCEPTION 'Platform ops membership required';
  END IF;

  IF v_status NOT IN ('pending', 'verified', 'rejected', 'unsubmitted') THEN
    RAISE EXCEPTION 'Invalid FSSAI verification status';
  END IF;

  UPDATE public.users
  SET
    fssai_verification_status = v_status,
    fssai_review_note = COALESCE(p_review_note, fssai_review_note),
    fssai_verified_at = CASE WHEN v_status = 'verified' THEN now() ELSE NULL END,
    fssai_reviewed_by = auth.uid()
  WHERE id = p_chef_id;

  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.ops_set_fssai_status(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ops_set_fssai_status(uuid, text, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Lock kitchen_live_signals (no anon open read/write)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.kitchen_live_signals') IS NULL THEN
    RAISE NOTICE 'kitchen_live_signals missing; skip RLS tighten';
    RETURN;
  END IF;

  REVOKE ALL ON public.kitchen_live_signals FROM anon;
  BEGIN
    REVOKE USAGE, SELECT ON SEQUENCE public.kitchen_live_signals_id_seq FROM anon;
  EXCEPTION
    WHEN undefined_table THEN NULL;
    WHEN undefined_object THEN NULL;
  END;

  GRANT SELECT, INSERT, DELETE ON public.kitchen_live_signals TO authenticated;
  GRANT ALL ON public.kitchen_live_signals TO service_role;

  DROP POLICY IF EXISTS kitchen_live_signals_select ON public.kitchen_live_signals;
  CREATE POLICY kitchen_live_signals_select ON public.kitchen_live_signals
    FOR SELECT
    TO authenticated
    USING (
      auth.uid() = room_id
      OR auth.uid()::text = sender_id
      OR (target_id IS NOT NULL AND auth.uid()::text = target_id)
    );

  DROP POLICY IF EXISTS kitchen_live_signals_insert ON public.kitchen_live_signals;
  CREATE POLICY kitchen_live_signals_insert ON public.kitchen_live_signals
    FOR INSERT
    TO authenticated
    WITH CHECK (
      auth.uid()::text = sender_id
      AND (
        auth.uid() = room_id
        OR EXISTS (
          SELECT 1 FROM public.chef_profiles cp
          WHERE cp.user_id = room_id AND coalesce(cp.is_live, false) = true
        )
      )
    );

  DROP POLICY IF EXISTS kitchen_live_signals_delete ON public.kitchen_live_signals;
  CREATE POLICY kitchen_live_signals_delete ON public.kitchen_live_signals
    FOR DELETE
    TO authenticated
    USING (auth.uid() = room_id OR auth.uid()::text = sender_id);
END $$;

NOTIFY pgrst, 'reload schema';
