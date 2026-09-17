-- Align checkout SQL with client offer rules, and give KYC ops kitchen pin fields.

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
  v_from timestamptz;
  v_until timestamptz;
  v_gated boolean := false;
  v_apply_offer boolean := true;
  v_line numeric;
  v_suffix numeric;
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
    COALESCE(NULLIF(to_jsonb(m)->>'promo_discount_value', '')::numeric, 0),
    NULLIF(to_jsonb(m)->>'offer_valid_from', '')::timestamptz,
    NULLIF(to_jsonb(m)->>'offer_valid_until', '')::timestamptz
  INTO v_list, v_offer, v_disc, v_meal_promo, v_promo_type, v_promo_val, v_from, v_until
  FROM public.meals m
  WHERE m.id = v_meal_id;

  IF v_list IS NULL THEN
    RETURN NULL;
  END IF;

  v_unit := GREATEST(v_list, 0);
  v_billed := v_qty;
  v_client_promo := nullif(upper(btrim(coalesce(p_item->>'promo_code', p_item->>'promoCode', ''))), '');
  v_gated := v_meal_promo IS NOT NULL AND coalesce(v_promo_val, 0) <= 0;

  IF v_from IS NOT NULL AND v_from > now() THEN
    v_apply_offer := false;
  END IF;
  IF v_until IS NOT NULL AND v_until < now() THEN
    v_apply_offer := false;
  END IF;
  IF v_gated AND (v_client_promo IS NULL OR upper(v_meal_promo) <> v_client_promo) THEN
    v_apply_offer := false;
  END IF;

  IF v_apply_offer THEN
    IF v_disc <= 0 AND v_meal_promo ~ '\d+$' THEN
      BEGIN
        v_suffix := substring(v_meal_promo from '\d+$')::numeric;
        IF v_suffix > 0 THEN
          v_disc := v_suffix;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END IF;

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
  END IF;

  IF v_meal_promo IS NOT NULL AND v_client_promo IS NOT NULL AND upper(v_meal_promo) = v_client_promo AND v_promo_val > 0 THEN
    IF v_promo_type LIKE '%percent%' THEN
      v_unit := ROUND(v_unit * (1 - LEAST(v_promo_val, 90) / 100.0), 2);
    ELSE
      v_unit := GREATEST(0, ROUND(v_unit - v_promo_val, 2));
    END IF;
  END IF;

  v_line := ROUND(GREATEST(v_unit, 0) * v_billed, 2);
  IF v_offer NOT LIKE '%bogo%' AND v_offer NOT LIKE '%buy%get%' THEN
    v_line := GREATEST(v_line, ROUND(GREATEST(v_list, 0) * v_qty * 0.60, 2));
  END IF;
  RETURN v_line;
END;
$$;

REVOKE ALL ON FUNCTION public.catalog_line_total(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.catalog_line_total(jsonb) TO authenticated, service_role;

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
        CASE
          WHEN btrim(coalesce(to_jsonb(u)->>'lat', '')) ~ '^-?[0-9]+(\.[0-9]+)?$'
          THEN (to_jsonb(u)->>'lat')::numeric
        END AS lat,
        CASE
          WHEN btrim(coalesce(to_jsonb(u)->>'lng', '')) ~ '^-?[0-9]+(\.[0-9]+)?$'
          THEN (to_jsonb(u)->>'lng')::numeric
        END AS lng,
        CASE
          WHEN btrim(coalesce(to_jsonb(u)->>'latitude', '')) ~ '^-?[0-9]+(\.[0-9]+)?$'
          THEN (to_jsonb(u)->>'latitude')::numeric
        END AS latitude,
        CASE
          WHEN btrim(coalesce(to_jsonb(u)->>'longitude', '')) ~ '^-?[0-9]+(\.[0-9]+)?$'
          THEN (to_jsonb(u)->>'longitude')::numeric
        END AS longitude,
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
