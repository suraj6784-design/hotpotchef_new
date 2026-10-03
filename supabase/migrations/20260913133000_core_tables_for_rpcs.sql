-- Core tables, indexes, and RLS required by HotPotChef RPCs and push webhooks.
--
-- Provenance: reconstructed from Flutter / edge-function call sites plus
-- incremental SQL recovered from prior repo history (orphan commits on the
-- same Supabase project ref tpcykyaumvqtwhuiiomg). Live `supabase db dump`
-- was not possible in this environment (no SUPABASE_ACCESS_TOKEN / service
-- role; placeholder anon key returns 401).
--
-- reconstructed from call sites — verify against hosted project before production
--
-- Safe to apply to an existing project: CREATE TABLE / ADD COLUMN IF NOT EXISTS.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_net;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_net not available in this environment: %', SQLERRM;
END $$;

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS supabase_vault;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'supabase_vault not available in this environment: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.users (
  id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  email text,
  name text,
  full_name text,
  phone text,
  role text,
  hotpot_coins numeric NOT NULL DEFAULT 0,
  fcm_token text,
  avatar_url text,
  address text,
  house_no text,
  street text,
  city text,
  state text,
  pincode text,
  lat numeric,
  lng numeric,
  fssai_number text,
  referral_code text,
  gateway_account_id text,
  payout_enabled boolean NOT NULL DEFAULT false,
  dob text,
  gender text,
  dietary_preference text,
  allergies text,
  emergency_phone text,
  pan_number text,
  blood_group text,
  vehicle_type text,
  vehicle_reg_no text,
  driving_license_no text,
  insurance_policy_no text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS email text,
  ADD COLUMN IF NOT EXISTS name text,
  ADD COLUMN IF NOT EXISTS full_name text,
  ADD COLUMN IF NOT EXISTS phone text,
  ADD COLUMN IF NOT EXISTS role text,
  ADD COLUMN IF NOT EXISTS hotpot_coins numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS fcm_token text,
  ADD COLUMN IF NOT EXISTS avatar_url text,
  ADD COLUMN IF NOT EXISTS address text,
  ADD COLUMN IF NOT EXISTS house_no text,
  ADD COLUMN IF NOT EXISTS street text,
  ADD COLUMN IF NOT EXISTS city text,
  ADD COLUMN IF NOT EXISTS state text,
  ADD COLUMN IF NOT EXISTS pincode text,
  ADD COLUMN IF NOT EXISTS lat numeric,
  ADD COLUMN IF NOT EXISTS lng numeric,
  ADD COLUMN IF NOT EXISTS fssai_number text,
  ADD COLUMN IF NOT EXISTS referral_code text,
  ADD COLUMN IF NOT EXISTS gateway_account_id text,
  ADD COLUMN IF NOT EXISTS payout_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS dob text,
  ADD COLUMN IF NOT EXISTS gender text,
  ADD COLUMN IF NOT EXISTS dietary_preference text,
  ADD COLUMN IF NOT EXISTS allergies text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- ---------------------------------------------------------------------------
-- meals (catalog). create-split-order also stamps payment metadata here
-- (pre-existing schema limitation — see supabase/functions/create-split-order).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.meals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chef_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  chef_name text,
  title text,
  name text,
  description text,
  price numeric NOT NULL DEFAULT 0,
  discounted_price numeric,
  quantity integer NOT NULL DEFAULT 0,
  category text,
  is_veg boolean NOT NULL DEFAULT true,
  time_slot text,
  exact_time text,
  service_type text,
  fssai_number text,
  hosting_address text,
  pickup_lat numeric,
  pickup_lng numeric,
  status text NOT NULL DEFAULT 'Available',
  image_url text,
  health_tags jsonb NOT NULL DEFAULT '[]'::jsonb,
  offer_type text,
  discount_value numeric,
  max_discount_cap numeric,
  promo_code text,
  promo_discount_type text,
  promo_discount_value numeric,
  accepts_hotpot_coins boolean NOT NULL DEFAULT true,
  offer_valid_from timestamptz,
  offer_valid_until timestamptz,
  platform_fee numeric,
  chef_payout_amount numeric,
  order_id text,
  transfer_status text,
  razorpay_transfer_id text,
  customer_name text,
  embedding vector(768),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.meals
  ADD COLUMN IF NOT EXISTS chef_id uuid,
  ADD COLUMN IF NOT EXISTS chef_name text,
  ADD COLUMN IF NOT EXISTS title text,
  ADD COLUMN IF NOT EXISTS name text,
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS price numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS discounted_price numeric,
  ADD COLUMN IF NOT EXISTS quantity integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS category text,
  ADD COLUMN IF NOT EXISTS is_veg boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS time_slot text,
  ADD COLUMN IF NOT EXISTS exact_time text,
  ADD COLUMN IF NOT EXISTS service_type text,
  ADD COLUMN IF NOT EXISTS fssai_number text,
  ADD COLUMN IF NOT EXISTS hosting_address text,
  ADD COLUMN IF NOT EXISTS pickup_lat numeric,
  ADD COLUMN IF NOT EXISTS pickup_lng numeric,
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'Available',
  ADD COLUMN IF NOT EXISTS image_url text,
  ADD COLUMN IF NOT EXISTS health_tags jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS offer_type text,
  ADD COLUMN IF NOT EXISTS discount_value numeric,
  ADD COLUMN IF NOT EXISTS max_discount_cap numeric,
  ADD COLUMN IF NOT EXISTS promo_code text,
  ADD COLUMN IF NOT EXISTS accepts_hotpot_coins boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS offer_valid_from timestamptz,
  ADD COLUMN IF NOT EXISTS offer_valid_until timestamptz,
  ADD COLUMN IF NOT EXISTS platform_fee numeric,
  ADD COLUMN IF NOT EXISTS chef_payout_amount numeric,
  ADD COLUMN IF NOT EXISTS order_id text,
  ADD COLUMN IF NOT EXISTS transfer_status text,
  ADD COLUMN IF NOT EXISTS razorpay_transfer_id text,
  ADD COLUMN IF NOT EXISTS customer_name text,
  ADD COLUMN IF NOT EXISTS embedding vector(768),
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS meals_chef_id_idx ON public.meals (chef_id);
CREATE INDEX IF NOT EXISTS meals_status_idx ON public.meals (status);
DO $$
BEGIN
  CREATE INDEX IF NOT EXISTS meals_embedding_ivfflat_idx
    ON public.meals
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 20);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Skipping meals embedding index: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- orders
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id text,
  customer_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  user_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  chef_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  driver_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  delivery_partner_id uuid REFERENCES public.users (id) ON DELETE SET NULL,
  source_meal_id uuid,
  items jsonb,
  cart_items jsonb,
  title text,
  quantity integer NOT NULL DEFAULT 1,
  status text NOT NULL DEFAULT 'Pending Chef Approval',
  order_type text,
  service_type text,
  total_price numeric NOT NULL DEFAULT 0,
  total_amount numeric NOT NULL DEFAULT 0,
  price numeric,
  payment_id text,
  razorpay_order_id text,
  razorpay_signature text,
  delivery_address text,
  pickup_address text,
  special_instructions text,
  customer_name text,
  customer_phone text,
  customer_email text,
  chef_name text,
  chef_lat numeric,
  chef_lng numeric,
  delivery_lat numeric,
  delivery_lng numeric,
  idempotency_key text,
  refund_id text,
  refund_status text,
  cancel_reason text,
  coins_applied numeric NOT NULL DEFAULT 0,
  delivery_fee numeric NOT NULL DEFAULT 0,
  packaging_fee numeric NOT NULL DEFAULT 0,
  tip_amount numeric NOT NULL DEFAULT 0,
  platform_margin numeric NOT NULL DEFAULT 0,
  driver_payout numeric NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  delivered_at timestamptz
);

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS order_id text,
  ADD COLUMN IF NOT EXISTS customer_id uuid,
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS chef_id uuid,
  ADD COLUMN IF NOT EXISTS driver_id uuid,
  ADD COLUMN IF NOT EXISTS delivery_partner_id uuid,
  ADD COLUMN IF NOT EXISTS source_meal_id uuid,
  ADD COLUMN IF NOT EXISTS items jsonb,
  ADD COLUMN IF NOT EXISTS cart_items jsonb,
  ADD COLUMN IF NOT EXISTS title text,
  ADD COLUMN IF NOT EXISTS quantity integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'Pending Chef Approval',
  ADD COLUMN IF NOT EXISTS order_type text,
  ADD COLUMN IF NOT EXISTS service_type text,
  ADD COLUMN IF NOT EXISTS total_price numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_amount numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS price numeric,
  ADD COLUMN IF NOT EXISTS payment_id text,
  ADD COLUMN IF NOT EXISTS razorpay_order_id text,
  ADD COLUMN IF NOT EXISTS razorpay_signature text,
  ADD COLUMN IF NOT EXISTS delivery_address text,
  ADD COLUMN IF NOT EXISTS pickup_address text,
  ADD COLUMN IF NOT EXISTS special_instructions text,
  ADD COLUMN IF NOT EXISTS customer_name text,
  ADD COLUMN IF NOT EXISTS customer_phone text,
  ADD COLUMN IF NOT EXISTS customer_email text,
  ADD COLUMN IF NOT EXISTS chef_name text,
  ADD COLUMN IF NOT EXISTS idempotency_key text,
  ADD COLUMN IF NOT EXISTS refund_id text,
  ADD COLUMN IF NOT EXISTS refund_status text,
  ADD COLUMN IF NOT EXISTS cancel_reason text,
  ADD COLUMN IF NOT EXISTS coins_applied numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS delivery_fee numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS packaging_fee numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS tip_amount numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS platform_margin numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS driver_payout numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS delivered_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS orders_idempotency_key_uidx
  ON public.orders (idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS orders_payment_id_uidx
  ON public.orders (payment_id)
  WHERE payment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS orders_chef_id_idx ON public.orders (chef_id);
CREATE INDEX IF NOT EXISTS orders_customer_id_idx ON public.orders (customer_id);
CREATE INDEX IF NOT EXISTS orders_driver_id_idx ON public.orders (driver_id);
CREATE INDEX IF NOT EXISTS orders_status_idx ON public.orders (status);

-- ---------------------------------------------------------------------------
-- Supporting tables the RPCs read / write
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.chef_profiles (
  user_id uuid PRIMARY KEY REFERENCES public.users (id) ON DELETE CASCADE,
  is_open boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.chef_profiles
  ADD COLUMN IF NOT EXISTS is_open boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE TABLE IF NOT EXISTS public.user_gamification (
  user_id uuid PRIMARY KEY REFERENCES public.users (id) ON DELETE CASCADE,
  current_streak integer NOT NULL DEFAULT 0,
  last_check_in_date date,
  loyalty_tier text NOT NULL DEFAULT 'Bronze Foodie 🥉',
  total_orders_completed integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_gamification
  ADD COLUMN IF NOT EXISTS current_streak integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_check_in_date date,
  ADD COLUMN IF NOT EXISTS loyalty_tier text NOT NULL DEFAULT 'Bronze Foodie 🥉',
  ADD COLUMN IF NOT EXISTS total_orders_completed integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS user_gamification_user_id_key
  ON public.user_gamification (user_id);

CREATE TABLE IF NOT EXISTS public.user_addresses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  house_no text,
  street text,
  address_line1 text,
  city text,
  state text,
  postal_code text,
  country text,
  landmark text,
  latitude numeric,
  longitude numeric,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_addresses
  ADD COLUMN IF NOT EXISTS is_default boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS postal_code text,
  ADD COLUMN IF NOT EXISTS address_line1 text,
  ADD COLUMN IF NOT EXISTS latitude numeric,
  ADD COLUMN IF NOT EXISTS longitude numeric;

CREATE TABLE IF NOT EXISTS public.carts (
  user_id uuid PRIMARY KEY REFERENCES public.users (id) ON DELETE CASCADE,
  items jsonb NOT NULL DEFAULT '[]'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.inventory_holds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  razorpay_order_id text NOT NULL,
  meal_id uuid NOT NULL,
  quantity integer NOT NULL CHECK (quantity > 0),
  status text NOT NULL DEFAULT 'held'
    CHECK (status IN ('held', 'confirmed', 'released')),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS inventory_holds_order_idx
  ON public.inventory_holds (razorpay_order_id);
CREATE INDEX IF NOT EXISTS inventory_holds_open_idx
  ON public.inventory_holds (status, expires_at)
  WHERE status = 'held';

CREATE TABLE IF NOT EXISTS public.pending_checkouts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  razorpay_order_id text UNIQUE NOT NULL,
  cart_items jsonb NOT NULL,
  delivery_address text,
  instructions text,
  phone text,
  email text,
  apply_coins boolean NOT NULL DEFAULT false,
  tip_amount numeric NOT NULL DEFAULT 0,
  delivery_fee numeric NOT NULL DEFAULT 0,
  amount_paise integer,
  dropoff_lat numeric,
  dropoff_lng numeric,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.pending_checkouts
  ADD COLUMN IF NOT EXISTS dropoff_lat numeric,
  ADD COLUMN IF NOT EXISTS dropoff_lng numeric,
  ADD COLUMN IF NOT EXISTS amount_paise integer;

CREATE TABLE IF NOT EXISTS public.wallets (
  user_id uuid PRIMARY KEY REFERENCES public.users (id) ON DELETE CASCADE,
  balance numeric NOT NULL DEFAULT 0,
  last_updated timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES public.users (id) ON DELETE CASCADE,
  amount numeric NOT NULL,
  transaction_type text NOT NULL,
  description text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT transactions_transaction_type_check
    CHECK (transaction_type = ANY (ARRAY[
      'earning', 'refund', 'payout', 'payment', 'credit', 'debit', 'redeem'
    ]))
);

ALTER TABLE public.transactions DROP CONSTRAINT IF EXISTS transactions_transaction_type_check;
ALTER TABLE public.transactions
  ADD CONSTRAINT transactions_transaction_type_check
  CHECK (transaction_type = ANY (ARRAY[
    'earning', 'refund', 'payout', 'payment', 'credit', 'debit', 'redeem'
  ]));

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chef_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_gamification ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.carts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_holds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pending_checkouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON public.users TO authenticated;
GRANT SELECT ON public.users TO anon;
GRANT ALL ON public.users TO service_role;

GRANT SELECT ON public.meals TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.meals TO authenticated;
GRANT ALL ON public.meals TO service_role;

GRANT SELECT, UPDATE ON public.orders TO authenticated;
GRANT ALL ON public.orders TO service_role;

GRANT SELECT, INSERT, UPDATE ON public.chef_profiles TO authenticated;
GRANT ALL ON public.chef_profiles TO service_role;

GRANT SELECT, INSERT, UPDATE ON public.user_gamification TO authenticated;
GRANT ALL ON public.user_gamification TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_addresses TO authenticated;
GRANT ALL ON public.user_addresses TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.carts TO authenticated;
GRANT ALL ON public.carts TO service_role;

GRANT SELECT ON public.inventory_holds TO authenticated;
GRANT ALL ON public.inventory_holds TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pending_checkouts TO authenticated;
GRANT ALL ON public.pending_checkouts TO service_role;

GRANT SELECT ON public.wallets TO authenticated;
GRANT ALL ON public.wallets TO service_role;

GRANT SELECT ON public.transactions TO authenticated;
GRANT ALL ON public.transactions TO service_role;

DROP POLICY IF EXISTS users_select ON public.users;
CREATE POLICY users_select ON public.users
  FOR SELECT TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS users_write_own ON public.users;
CREATE POLICY users_write_own ON public.users
  FOR ALL TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS meals_select ON public.meals;
CREATE POLICY meals_select ON public.meals
  FOR SELECT TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS meals_write_own ON public.meals;
CREATE POLICY meals_write_own ON public.meals
  FOR ALL TO authenticated
  USING (auth.uid() = chef_id)
  WITH CHECK (auth.uid() = chef_id);

DROP POLICY IF EXISTS orders_select_involved ON public.orders;
CREATE POLICY orders_select_involved ON public.orders
  FOR SELECT TO authenticated
  USING (
    auth.uid() = customer_id
    OR auth.uid() = user_id
    OR auth.uid() = chef_id
    OR auth.uid() = driver_id
    OR auth.uid() = delivery_partner_id
  );

DROP POLICY IF EXISTS orders_update_involved ON public.orders;
CREATE POLICY orders_update_involved ON public.orders
  FOR UPDATE TO authenticated
  USING (
    auth.uid() = customer_id
    OR auth.uid() = user_id
    OR auth.uid() = chef_id
    OR auth.uid() = driver_id
    OR auth.uid() = delivery_partner_id
  )
  WITH CHECK (
    auth.uid() = customer_id
    OR auth.uid() = user_id
    OR auth.uid() = chef_id
    OR auth.uid() = driver_id
    OR auth.uid() = delivery_partner_id
  );

DROP POLICY IF EXISTS chef_profiles_select ON public.chef_profiles;
CREATE POLICY chef_profiles_select ON public.chef_profiles
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS chef_profiles_write ON public.chef_profiles;
CREATE POLICY chef_profiles_write ON public.chef_profiles
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS user_gamification_own ON public.user_gamification;
CREATE POLICY user_gamification_own ON public.user_gamification
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS user_addresses_own ON public.user_addresses;
CREATE POLICY user_addresses_own ON public.user_addresses
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS carts_own ON public.carts;
CREATE POLICY carts_own ON public.carts
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS inventory_holds_own ON public.inventory_holds;
CREATE POLICY inventory_holds_own ON public.inventory_holds
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS pending_checkouts_own ON public.pending_checkouts;
CREATE POLICY pending_checkouts_own ON public.pending_checkouts
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS wallets_own ON public.wallets;
CREATE POLICY wallets_own ON public.wallets
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS transactions_select ON public.transactions;
CREATE POLICY transactions_select ON public.transactions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Realtime streams used by chef hub / customer orders / meal stock.
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
EXCEPTION
  WHEN undefined_object THEN NULL;
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.meals;
EXCEPTION
  WHEN undefined_object THEN NULL;
  WHEN duplicate_object THEN NULL;
END $$;

NOTIFY pgrst, 'reload schema';
