-- Place and charge the same plate price the checkout screen shows.
-- Expired offers, the discount cap, and the 60% floor match the diner app.
-- Add-on prices still come from meals.add_ons.

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
  v_cap numeric;
  v_gross numeric;
  v_net numeric;
  v_off numeric;
  v_meal_promo text;
  v_promo_type text;
  v_promo_val numeric;
  v_promo_cap numeric;
  v_client_promo text;
  v_from timestamptz;
  v_until timestamptz;
  v_in_window boolean := true;
  v_apply_offer boolean := true;
  v_suffix numeric;
  v_addon jsonb;
  v_addon_unit numeric := 0;
  v_addons jsonb;
  v_catalog_addons jsonb;
  v_cat jsonb;
  v_pick_id text;
  v_pick_title text;
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
    COALESCE(NULLIF(to_jsonb(m)->>'max_discount_cap', '')::numeric, 0),
    nullif(btrim(coalesce(to_jsonb(m)->>'promo_code', '')), ''),
    lower(coalesce(to_jsonb(m)->>'promo_discount_type', '')),
    COALESCE(NULLIF(to_jsonb(m)->>'promo_discount_value', '')::numeric, 0),
    COALESCE(NULLIF(to_jsonb(m)->>'promo_max_discount_cap', '')::numeric, 0),
    NULLIF(to_jsonb(m)->>'offer_valid_from', '')::timestamptz,
    NULLIF(to_jsonb(m)->>'offer_valid_until', '')::timestamptz,
    COALESCE(m.add_ons, '[]'::jsonb)
  INTO v_list, v_offer, v_disc, v_cap, v_meal_promo, v_promo_type, v_promo_val, v_promo_cap,
       v_from, v_until, v_catalog_addons
  FROM public.meals m
  WHERE m.id = v_meal_id;

  IF v_list IS NULL THEN
    RETURN NULL;
  END IF;

  v_list := GREATEST(v_list, 0);
  v_gross := ROUND(v_list * v_qty, 2);
  v_net := v_gross;

  IF v_from IS NOT NULL AND v_from > now() THEN
    v_in_window := false;
  END IF;
  IF v_until IS NOT NULL AND v_until < now() THEN
    v_in_window := false;
  END IF;

  v_client_promo := nullif(upper(btrim(coalesce(
    p_item->>'applied_promo_code',
    p_item->>'promo_code',
    p_item->>'promoCode',
    ''
  ))), '');

  v_apply_offer := v_in_window;
  IF v_meal_promo IS NOT NULL AND coalesce(v_promo_val, 0) <= 0
     AND (v_client_promo IS NULL OR upper(v_meal_promo) <> v_client_promo) THEN
    v_apply_offer := false;
  END IF;

  IF v_apply_offer THEN
    IF v_disc <= 0 AND v_meal_promo ~ '\d+$' THEN
      BEGIN
        v_suffix := substring(v_meal_promo from '\d+$')::numeric;
        IF v_suffix > 0 AND (v_offer LIKE '%flat%' OR v_suffix <= 90) THEN
          v_disc := v_suffix;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END IF;
    IF v_disc <= 0 AND v_offer LIKE '%flash%' THEN
      v_disc := 20;
    END IF;

    IF v_offer LIKE '%bogo%' OR v_offer LIKE '%buy%get%' THEN
      v_net := ROUND(v_list * ((v_qty + 1) / 2), 2);
    ELSIF v_offer LIKE '%percent%' OR v_offer LIKE '%flash%' THEN
      IF v_disc > 0 THEN
        v_off := ROUND(v_list * (LEAST(v_disc, 90) / 100.0) * v_qty, 2);
        IF v_cap > 0 THEN
          v_off := LEAST(v_off, v_cap);
        END IF;
        v_net := GREATEST(0, ROUND(v_gross - v_off, 2));
      END IF;
    ELSIF v_offer LIKE '%flat%' THEN
      v_off := ROUND(LEAST(v_list, GREATEST(v_disc, 0)) * v_qty, 2);
      IF v_cap > 0 THEN
        v_off := LEAST(v_off, v_cap);
      END IF;
      v_net := GREATEST(0, ROUND(v_gross - v_off, 2));
    END IF;
  END IF;

  IF v_in_window AND v_meal_promo IS NOT NULL AND v_client_promo IS NOT NULL
     AND upper(v_meal_promo) = v_client_promo AND v_promo_val > 0 THEN
    IF v_promo_type LIKE '%flat%' THEN
      v_off := LEAST(v_net, GREATEST(v_promo_val, 0));
    ELSE
      v_off := ROUND(v_net * (LEAST(v_promo_val, 100) / 100.0), 2);
    END IF;
    IF v_promo_cap > 0 THEN
      v_off := LEAST(v_off, v_promo_cap);
    END IF;
    v_net := GREATEST(0, ROUND(v_net - v_off, 2));
  END IF;

  IF v_offer NOT LIKE '%bogo%' AND v_offer NOT LIKE '%buy%get%' AND v_gross > 0 THEN
    v_net := GREATEST(v_net, ROUND(v_gross * 0.60, 2));
  END IF;

  v_addons := COALESCE(p_item->'selectedAddOns', p_item->'selected_addons', p_item->'addOns', '[]'::jsonb);
  IF jsonb_typeof(v_addons) = 'array' AND jsonb_typeof(COALESCE(v_catalog_addons, '[]'::jsonb)) = 'array' THEN
    FOR v_addon IN SELECT * FROM jsonb_array_elements(v_addons)
    LOOP
      v_pick_id := lower(btrim(coalesce(v_addon->>'id', '')));
      v_pick_title := lower(btrim(coalesce(v_addon->>'title', v_addon->>'name', '')));
      FOR v_cat IN SELECT * FROM jsonb_array_elements(COALESCE(v_catalog_addons, '[]'::jsonb))
      LOOP
        IF (v_pick_id <> '' AND lower(btrim(coalesce(v_cat->>'id', ''))) = v_pick_id)
          OR (
            v_pick_title <> ''
            AND lower(btrim(coalesce(v_cat->>'title', v_cat->>'name', ''))) = v_pick_title
          )
        THEN
          BEGIN
            v_addon_unit := v_addon_unit + COALESCE(NULLIF(v_cat->>'price', '')::numeric, 0);
          EXCEPTION WHEN OTHERS THEN
            NULL;
          END;
          EXIT;
        END IF;
      END LOOP;
    END LOOP;
  END IF;

  RETURN ROUND(v_net + GREATEST(v_addon_unit, 0) * v_qty, 2);
END;
$$;

-- The Razorpay charge and the saved order both use the live menu price.
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
  v_packaging numeric := 0;
BEGIN
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RETURN jsonb_build_object(
      'items_total', 0,
      'item_total', 0,
      'subtotal', 0,
      'packaging_fee', 0,
      'total', 0
    );
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_line := public.catalog_line_total(v_item);
    IF v_line IS NULL THEN
      RETURN jsonb_build_object(
        'items_total', 0,
        'item_total', 0,
        'subtotal', 0,
        'packaging_fee', 0,
        'total', 0
      );
    END IF;
    v_food := v_food + v_line;
  END LOOP;

  v_packaging := public.packaging_fee_from_food_total(v_food);

  RETURN jsonb_build_object(
    'items_total', ROUND(v_food, 2),
    'item_total', ROUND(v_food, 2),
    'subtotal', ROUND(v_food, 2),
    'packaging_fee', v_packaging,
    'total', ROUND(v_food + v_packaging, 2)
  );
END;
$$;
