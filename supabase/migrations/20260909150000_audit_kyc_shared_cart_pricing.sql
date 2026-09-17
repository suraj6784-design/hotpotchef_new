-- Audit: shared-cart RLS, catalog-priced checkout, KYC/accounts RPCs, ops audit, owner email setting.

CREATE TABLE IF NOT EXISTS public.platform_settings (
  key text PRIMARY KEY,
  value text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.platform_settings (key, value)
VALUES ('owner_email', 'suraj6784@gmail.com')
ON CONFLICT (key) DO NOTHING;

ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.platform_settings FROM PUBLIC, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.platform_settings TO service_role;

CREATE OR REPLACE FUNCTION public.platform_owner_email()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT lower(trim(coalesce(
    (SELECT value FROM public.platform_settings WHERE key = 'owner_email' LIMIT 1),
    'suraj6784@gmail.com'
  )));
$$;

CREATE TABLE IF NOT EXISTS public.shared_cart_members (
  room_code text NOT NULL,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (room_code, user_id)
);

CREATE INDEX IF NOT EXISTS shared_cart_members_user_idx ON public.shared_cart_members (user_id);

ALTER TABLE public.shared_cart_members ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON public.shared_cart_members TO authenticated;
GRANT ALL ON public.shared_cart_members TO service_role;

DROP POLICY IF EXISTS shared_cart_members_select ON public.shared_cart_members;
CREATE POLICY shared_cart_members_select ON public.shared_cart_members
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_platform_ops());

DROP POLICY IF EXISTS shared_cart_members_insert ON public.shared_cart_members;
CREATE POLICY shared_cart_members_insert ON public.shared_cart_members
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

INSERT INTO public.shared_cart_members (room_code, user_id)
SELECT sc.room_code, sc.host_id
FROM public.shared_carts sc
ON CONFLICT DO NOTHING;

DROP POLICY IF EXISTS shared_carts_update ON public.shared_carts;
CREATE POLICY shared_carts_update ON public.shared_carts
  FOR UPDATE
  TO authenticated
  USING (
    auth.uid() = host_id
    OR EXISTS (
      SELECT 1 FROM public.shared_cart_members m
      WHERE m.room_code = shared_carts.room_code AND m.user_id = auth.uid()
    )
  )
  WITH CHECK (
    auth.uid() = host_id
    OR EXISTS (
      SELECT 1 FROM public.shared_cart_members m
      WHERE m.room_code = shared_carts.room_code AND m.user_id = auth.uid()
    )
  );

CREATE OR REPLACE FUNCTION public.join_shared_cart(p_room_code text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text := upper(trim(coalesce(p_room_code, '')));
  v_host uuid;
BEGIN
  IF auth.uid() IS NULL OR v_code = '' THEN
    RETURN false;
  END IF;
  SELECT host_id INTO v_host FROM public.shared_carts WHERE room_code = v_code;
  IF v_host IS NULL THEN
    RAISE EXCEPTION 'Group cart not found';
  END IF;
  INSERT INTO public.shared_cart_members (room_code, user_id)
  VALUES (v_code, auth.uid())
  ON CONFLICT DO NOTHING;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.join_shared_cart(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.join_shared_cart(text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalog_line_total(p_item jsonb)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_meal_id uuid;
  v_qty int;
  v_list numeric;
  v_offer text;
  v_disc numeric;
  v_unit numeric;
  v_billed int;
  v_promo_code text;
  v_meal_promo text;
  v_promo_type text;
  v_promo_val numeric;
  v_client_promo text;
BEGIN
  BEGIN
    v_meal_id := NULLIF(COALESCE(
      p_item->>'source_meal_id',
      p_item->>'meal_id',
      p_item->>'mealId',
      p_item->>'id'
    ), '')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
  IF v_meal_id IS NULL THEN
    RETURN NULL;
  END IF;

  BEGIN
    v_qty := GREATEST(1, COALESCE(round(NULLIF(p_item->>'quantity', '')::numeric), NULLIF(p_item->>'qty', '')::numeric, 1)::int);
  EXCEPTION WHEN OTHERS THEN
    v_qty := 1;
  END;

  SELECT
    COALESCE(m.price, 0),
    lower(coalesce(to_jsonb(m)->>'offer_type', '')),
    COALESCE(NULLIF(to_jsonb(m)->>'discount_value', '')::numeric, 0),
    nullif(btrim(coalesce(to_jsonb(m)->>'promo_code', '')), ''),
    lower(coalesce(to_jsonb(m)->>'promo_discount_type', '')),
    COALESCE(NULLIF(to_jsonb(m)->>'promo_discount_value', '')::numeric, 0)
  INTO v_list, v_offer, v_disc, v_meal_promo, v_promo_type, v_promo_val
  FROM public.meals m
  WHERE m.id = v_meal_id;

  IF v_list IS NULL THEN
    RETURN NULL;
  END IF;

  v_unit := GREATEST(v_list, 0);
  v_billed := v_qty;

  IF v_offer LIKE '%bogo%' OR v_offer LIKE '%buy%get%' THEN
    v_billed := (v_qty + 1) / 2;
  ELSIF v_offer LIKE '%percent%' OR v_offer LIKE '%flash%' THEN
    IF v_disc <= 0 AND v_offer LIKE '%flash%' THEN
      v_disc := 20;
    END IF;
    IF v_disc > 0 THEN
      v_unit := ROUND(v_list * (1 - LEAST(v_disc, 90) / 100.0), 2);
    END IF;
  ELSIF v_offer LIKE '%flat%' THEN
    v_unit := GREATEST(0, ROUND(v_list - GREATEST(v_disc, 0), 2));
  END IF;

  v_client_promo := nullif(upper(btrim(coalesce(p_item->>'promo_code', p_item->>'promoCode', ''))), '');
  IF v_meal_promo IS NOT NULL AND v_client_promo IS NOT NULL AND upper(v_meal_promo) = v_client_promo AND v_promo_val > 0 THEN
    IF v_promo_type LIKE '%percent%' THEN
      v_unit := ROUND(v_unit * (1 - LEAST(v_promo_val, 90) / 100.0), 2);
    ELSE
      v_unit := GREATEST(0, ROUND(v_unit - v_promo_val, 2));
    END IF;
  END IF;

  RETURN ROUND(GREATEST(v_unit, 0) * v_billed, 2);
END;
$$;

REVOKE ALL ON FUNCTION public.catalog_line_total(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.catalog_line_total(jsonb) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.calculate_cart_total(p_items jsonb, p_user_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_item jsonb;
  v_line numeric;
  v_food numeric := 0;
  v_packaging numeric := 20;
BEGIN
  v_packaging := public.packaging_fee_for_cart(COALESCE(p_user_id, auth.uid()), COALESCE(p_items, '[]'::jsonb));

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RETURN jsonb_build_object(
      'items_total', 0,
      'item_total', 0,
      'subtotal', 0,
      'packaging_fee', v_packaging,
      'total', v_packaging
    );
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_line := public.catalog_line_total(v_item);
    IF v_line IS NULL THEN
      RAISE EXCEPTION 'A plate in this cart is no longer on the menu';
    END IF;
    v_food := v_food + v_line;
  END LOOP;

  RETURN jsonb_build_object(
    'items_total', ROUND(v_food, 2),
    'item_total', ROUND(v_food, 2),
    'subtotal', ROUND(v_food, 2),
    'packaging_fee', v_packaging,
    'total', ROUND(v_food + v_packaging, 2)
  );
END;
$$;

CREATE TABLE IF NOT EXISTS public.platform_ops_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid,
  action text NOT NULL,
  target_table text,
  target_id text,
  detail jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS platform_ops_audit_created_idx ON public.platform_ops_audit (created_at DESC);

ALTER TABLE public.platform_ops_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.platform_ops_audit FROM PUBLIC, authenticated;
GRANT SELECT ON public.platform_ops_audit TO authenticated;
GRANT ALL ON public.platform_ops_audit TO service_role;

DROP POLICY IF EXISTS platform_ops_audit_select ON public.platform_ops_audit;
CREATE POLICY platform_ops_audit_select ON public.platform_ops_audit
  FOR SELECT TO authenticated
  USING (public.ops_has_permission('audit') OR public.is_platform_owner());

CREATE OR REPLACE FUNCTION public.ops_audit_write(
  p_action text,
  p_target_table text DEFAULT NULL,
  p_target_id text DEFAULT NULL,
  p_detail jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_ops() THEN
    RETURN;
  END IF;
  INSERT INTO public.platform_ops_audit (actor_id, action, target_table, target_id, detail)
  VALUES (auth.uid(), left(trim(coalesce(p_action, 'update')), 80), p_target_table, p_target_id, coalesce(p_detail, '{}'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.ops_audit_users_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_platform_ops() THEN
    RETURN NEW;
  END IF;
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    PERFORM public.ops_audit_write('set_role', 'users', NEW.id::text, jsonb_build_object('from', OLD.role, 'to', NEW.role));
  END IF;
  IF NEW.account_status IS DISTINCT FROM OLD.account_status THEN
    PERFORM public.ops_audit_write('set_account_status', 'users', NEW.id::text, jsonb_build_object('from', OLD.account_status, 'to', NEW.account_status));
  END IF;
  IF NEW.fssai_verification_status IS DISTINCT FROM OLD.fssai_verification_status THEN
    PERFORM public.ops_audit_write('set_fssai', 'users', NEW.id::text, jsonb_build_object('from', OLD.fssai_verification_status, 'to', NEW.fssai_verification_status));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ops_audit_users ON public.users;
CREATE TRIGGER ops_audit_users
  AFTER UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.ops_audit_users_trg();

CREATE OR REPLACE FUNCTION public.ops_audit_simple_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_platform_ops() THEN
    RETURN NEW;
  END IF;
  PERFORM public.ops_audit_write(
    TG_TABLE_NAME || '_status',
    TG_TABLE_NAME,
    NEW.id::text,
    jsonb_build_object('status', NEW.status)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ops_audit_tickets ON public.support_tickets;
CREATE TRIGGER ops_audit_tickets
  AFTER UPDATE OF status ON public.support_tickets
  FOR EACH ROW
  EXECUTE FUNCTION public.ops_audit_simple_trg();

DROP TRIGGER IF EXISTS ops_audit_meals ON public.meals;
CREATE TRIGGER ops_audit_meals
  AFTER UPDATE OF status ON public.meals
  FOR EACH ROW
  EXECUTE FUNCTION public.ops_audit_simple_trg();

CREATE OR REPLACE FUNCTION public.ops_list_kyc_queue()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.ops_has_permission('kyc') THEN
    RAISE EXCEPTION 'KYC ops permission required';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(row_to_json(q)::jsonb ORDER BY q.incomplete DESC, q.done)
    FROM (
      SELECT
        u.id,
        u.role,
        u.name,
        u.full_name,
        u.email,
        u.phone,
        u.fssai_number,
        u.fssai_proof_url,
        u.fssai_verification_status,
        u.gstin,
        CASE
          WHEN coalesce(to_jsonb(u)->>'bank_account_number', '') = '' THEN NULL
          ELSE '****' || right(replace(to_jsonb(u)->>'bank_account_number', ' ', ''), 4)
        END AS bank_account_number,
        to_jsonb(u)->>'bank_ifsc' AS bank_ifsc,
        CASE
          WHEN coalesce(to_jsonb(u)->>'pan_number', '') = '' THEN NULL
          ELSE left(to_jsonb(u)->>'pan_number', 2) || '******' || right(to_jsonb(u)->>'pan_number', 2)
        END AS pan_number,
        to_jsonb(u)->>'aadhaar_masked' AS aadhaar_masked,
        to_jsonb(u)->>'vehicle_type' AS vehicle_type,
        to_jsonb(u)->>'vehicle_reg_no' AS vehicle_reg_no,
        to_jsonb(u)->>'vehicle_number' AS vehicle_number,
        cp.local_kitchen_name,
        0 AS done,
        false AS incomplete
      FROM public.users u
      LEFT JOIN public.chef_profiles cp ON cp.user_id = u.id
      WHERE lower(u.role::text) IN ('chef', 'driver')
      LIMIT 120
    ) q
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.ops_list_kyc_queue() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ops_list_kyc_queue() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ops_list_accounts()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.ops_has_permission('accounts') AND NOT public.is_platform_owner() THEN
    RAISE EXCEPTION 'Accounts ops permission required';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id', u.id,
      'role', u.role,
      'name', u.name,
      'full_name', u.full_name,
      'email', u.email,
      'phone', u.phone,
      'account_status', u.account_status
    ))
    FROM (
      SELECT id, role, name, full_name, email, phone, account_status
      FROM public.users
      LIMIT 200
    ) u
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.ops_list_accounts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ops_list_accounts() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ops_desk_counts()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.ops_has_permission('dashboard') THEN
    RAISE EXCEPTION 'Dashboard ops permission required';
  END IF;
  RETURN jsonb_build_object(
    'open_tickets', (SELECT count(*) FROM public.support_tickets WHERE status IN ('open', 'pending_customer', 'pending_ops')),
    'live_meals', (SELECT count(*) FROM public.meals WHERE lower(coalesce(status, '')) = 'available'),
    'user_count', (SELECT count(*) FROM public.users)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.ops_desk_counts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ops_desk_counts() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ops_list_audit(p_limit int DEFAULT 80)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.ops_has_permission('audit') AND NOT public.is_platform_owner() THEN
    RAISE EXCEPTION 'Audit permission required';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(to_jsonb(a) ORDER BY a.created_at DESC)
    FROM (
      SELECT id, actor_id, action, target_table, target_id, detail, created_at
      FROM public.platform_ops_audit
      ORDER BY created_at DESC
      LIMIT GREATEST(1, LEAST(coalesce(p_limit, 80), 200))
    ) a
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.ops_list_audit(int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ops_list_audit(int) TO authenticated, service_role;

DROP POLICY IF EXISTS users_select_platform_ops_kyc ON public.users;
CREATE POLICY users_select_platform_ops_kyc ON public.users
  FOR SELECT TO authenticated
  USING (
    public.ops_has_permission('kyc')
    OR public.ops_has_permission('accounts')
    OR public.is_platform_owner()
  );

NOTIFY pgrst, 'reload schema';
