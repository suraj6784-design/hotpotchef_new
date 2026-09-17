-- RLS lockdown for public.meals and public.orders.
--
-- Documents the live HotPotChef project (tpcykyaumvqtwhuiiomg) after the
-- 2026-09-14 audit. Anonymous PATCH on meals/orders previously returned HTTP
-- 204 because of USING (true) policies. Live already dropped those; this file
-- is idempotent so git and a fresh `db reset` match.
--
-- SAFE: DROP POLICY / CREATE POLICY / REVOKE column grants only.
-- Does NOT CREATE TABLE, DROP TABLE, or reconstruct core schema.

-- Policy expressions call is_platform_ops(). Stub it on fresh reconstructed DBs.
DO $$
BEGIN
  IF to_regprocedure('public.is_platform_ops()') IS NULL THEN
    EXECUTE $fn$
      CREATE FUNCTION public.is_platform_ops()
      RETURNS boolean
      LANGUAGE sql
      STABLE
      SECURITY DEFINER
      SET search_path = public
      AS $body$ SELECT false $body$;
    $fn$;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- meals: drop legacy wide-open policies (names from live + reconstructed git)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Allow all operations on meals" ON public.meals;
DROP POLICY IF EXISTS "Enable all access for meals" ON public.meals;
DROP POLICY IF EXISTS meals_all ON public.meals;
DROP POLICY IF EXISTS meals_select ON public.meals;
DROP POLICY IF EXISTS meals_write_own ON public.meals;
DROP POLICY IF EXISTS meals_anon_all ON public.meals;

DROP POLICY IF EXISTS meals_select_available_or_own ON public.meals;
CREATE POLICY meals_select_available_or_own
  ON public.meals
  FOR SELECT
  TO anon, authenticated
  USING (
    chef_id = auth.uid()
    OR lower(COALESCE(status, '')) = 'available'
  );

DROP POLICY IF EXISTS meals_insert_own_chef ON public.meals;
CREATE POLICY meals_insert_own_chef
  ON public.meals
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = chef_id);

DROP POLICY IF EXISTS meals_update_own_chef_or_ops ON public.meals;
CREATE POLICY meals_update_own_chef_or_ops
  ON public.meals
  FOR UPDATE
  TO authenticated
  USING (
    auth.uid() = chef_id
    OR (
      EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'is_platform_ops'
      )
      AND is_platform_ops()
    )
  )
  WITH CHECK (
    auth.uid() = chef_id
    OR (
      EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'is_platform_ops'
      )
      AND is_platform_ops()
    )
  );

DROP POLICY IF EXISTS "Enable delete for users based on chef_id" ON public.meals;
CREATE POLICY "Enable delete for users based on chef_id"
  ON public.meals
  FOR DELETE
  TO authenticated
  USING (auth.uid() = chef_id);

GRANT SELECT ON public.meals TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.meals TO authenticated;
GRANT ALL ON public.meals TO service_role;

-- Catalog must not leak payout math / transfer ids to the publishable key.
-- FSSAI numbers stay chef-visible via RLS (own rows) + authenticated SELECT
-- of remaining columns; anon cannot read these columns at all.
REVOKE SELECT (
  platform_fee,
  chef_payout_amount,
  transfer_status,
  razorpay_transfer_id,
  fssai_number
) ON public.meals FROM anon, PUBLIC;

-- ---------------------------------------------------------------------------
-- orders: drop USING (true) write policies
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Chefs and Drivers update orders" ON public.orders;
DROP POLICY IF EXISTS "Allow all operations on orders" ON public.orders;
DROP POLICY IF EXISTS orders_all ON public.orders;
DROP POLICY IF EXISTS orders_anon_all ON public.orders;
DROP POLICY IF EXISTS orders_update_involved ON public.orders;

DROP POLICY IF EXISTS orders_update_participants ON public.orders;
CREATE POLICY orders_update_participants
  ON public.orders
  FOR UPDATE
  TO authenticated
  USING (
    auth.uid() = customer_id
    OR auth.uid() = chef_id
    OR auth.uid() = driver_id
    OR auth.uid() = delivery_partner_id
    OR (
      EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'is_platform_ops'
      )
      AND is_platform_ops()
    )
  )
  WITH CHECK (
    auth.uid() = customer_id
    OR auth.uid() = chef_id
    OR auth.uid() = driver_id
    OR auth.uid() = delivery_partner_id
    OR (
      EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'is_platform_ops'
      )
      AND is_platform_ops()
    )
  );

DROP POLICY IF EXISTS "Customers insert orders" ON public.orders;
CREATE POLICY "Customers insert orders"
  ON public.orders
  FOR INSERT
  TO public
  WITH CHECK (auth.uid() = customer_id);

REVOKE ALL ON public.orders FROM anon;
GRANT SELECT, UPDATE ON public.orders TO authenticated;
GRANT INSERT ON public.orders TO authenticated;
GRANT ALL ON public.orders TO service_role;

-- ---------------------------------------------------------------------------
-- formatted_accounts_view leaked emails to anon in the audit.
-- Revoke if the view exists; do not CREATE it here.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.formatted_accounts_view') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON public.formatted_accounts_view FROM anon, public';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
