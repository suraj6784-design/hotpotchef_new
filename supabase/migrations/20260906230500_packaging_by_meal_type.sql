-- Shelf / hamper carts should not always pay hot-thali packaging.

CREATE OR REPLACE FUNCTION public.packaging_fee_for_cart(
  p_user_id uuid,
  p_cart_items jsonb
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_base numeric := public.packaging_fee_for_loyalty(p_user_id);
  v_item jsonb;
  v_hot int := 0;
  v_hamper int := 0;
  v_shelf int := 0;
  v_flag text;
  v_kind text;
  v_cat text;
BEGIN
  IF p_cart_items IS NULL OR jsonb_typeof(p_cart_items) <> 'array' OR jsonb_array_length(p_cart_items) = 0 THEN
    RETURN v_base;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_cart_items)
  LOOP
    v_flag := lower(coalesce(
      v_item->>'is_shelf_item',
      v_item->'rawMealDetails'->>'is_shelf_item',
      ''
    ));
    v_kind := lower(coalesce(
      v_item->>'shelf_kind',
      v_item->'rawMealDetails'->>'shelf_kind',
      ''
    ));
    v_cat := lower(coalesce(
      v_item->>'category',
      v_item->'rawMealDetails'->>'category',
      ''
    ));
    IF v_flag IN ('true', 't', '1', 'yes')
       OR v_kind <> ''
       OR v_cat LIKE '%shelf%'
       OR v_cat LIKE '%pantry%' THEN
      v_shelf := v_shelf + 1;
      CONTINUE;
    END IF;

    v_flag := lower(coalesce(
      v_item->>'is_hamper',
      v_item->'rawMealDetails'->>'is_hamper',
      ''
    ));
    IF v_flag IN ('true', 't', '1', 'yes')
       OR v_cat LIKE '%hamper%'
       OR v_cat LIKE '%festival%' THEN
      v_hamper := v_hamper + 1;
      CONTINUE;
    END IF;

    v_hot := v_hot + 1;
  END LOOP;

  IF v_hot > 0 THEN
    RETURN v_base;
  END IF;
  IF v_shelf > 0 AND v_hamper = 0 THEN
    RETURN 0;
  END IF;
  IF v_hamper > 0 THEN
    RETURN LEAST(v_base, 10);
  END IF;
  RETURN v_base;
END;
$$;

REVOKE ALL ON FUNCTION public.packaging_fee_for_cart(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.packaging_fee_for_cart(uuid, jsonb) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.calculate_cart_total(p_items jsonb, p_user_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_item jsonb;
  v_qty int;
  v_unit numeric;
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
    BEGIN
      v_qty := GREATEST(1, COALESCE(round(NULLIF(v_item->>'quantity', '')::numeric), 1)::int);
    EXCEPTION WHEN OTHERS THEN
      v_qty := 1;
    END;

    BEGIN
      v_unit := COALESCE(
        NULLIF(v_item->>'discounted_price', '')::numeric,
        NULLIF(v_item->>'price', '')::numeric,
        NULLIF(v_item->>'base_price', '')::numeric,
        0
      );
    EXCEPTION WHEN OTHERS THEN
      v_unit := 0;
    END;

    v_food := v_food + (GREATEST(v_unit, 0) * v_qty);
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

REVOKE ALL ON FUNCTION public.calculate_cart_total(jsonb, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.calculate_cart_total(jsonb, uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
