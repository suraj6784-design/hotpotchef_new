-- Revert catalog reconstruction from order lines (Daily 11–9 slots, title clones).
-- Keep each published meal UUID that appeared on a paid (price > 0) order before
-- 1 Sep 2026 IST. Do not invent a daily window. Skip ₹0 lines and ₹0 orders.

WITH lines AS (
  SELECT
    o.created_at AS ordered_at,
    o.chef_id AS order_chef_id,
    e AS item
  FROM public.orders o
  CROSS JOIN LATERAL jsonb_array_elements(
    CASE
      WHEN jsonb_typeof(to_jsonb(o.items)) = 'array' THEN to_jsonb(o.items)
      WHEN jsonb_typeof(to_jsonb(o.items)) = 'string' THEN COALESCE(NULLIF(btrim(o.items::text), '')::jsonb, '[]'::jsonb)
      ELSE '[]'::jsonb
    END
  ) e
  WHERE o.created_at < timestamptz '2026-09-01 00:00:00+05:30'
    AND coalesce(o.total_price, 0) > 0
),
normalized AS (
  SELECT
    ordered_at,
    coalesce(
      NULLIF(item->>'chef_id', '')::uuid,
      NULLIF(item->>'chefId', '')::uuid,
      order_chef_id
    ) AS chef_id,
    NULLIF(coalesce(item->>'id', item->>'meal_id', item->>'source_meal_id', item->>'mealId'), '')::uuid AS meal_id,
    nullif(btrim(coalesce(item->>'title', item->>'name', item->>'meal_name', '')), '') AS title,
    coalesce(NULLIF(item->>'price', '')::numeric, 0) AS price,
    greatest(coalesce(NULLIF(item->>'quantity', '')::int, 1), 1) AS quantity,
    coalesce(item->>'service_type', item->>'selected_service_type', 'Delivery (Platform)') AS service_type,
    nullif(btrim(coalesce(item->>'time_slot', item->>'timeSlot', '')), '') AS time_slot,
    item->>'image_url' AS image_url,
    item->>'description' AS description,
    item->>'chef_name' AS chef_name,
    item->>'category' AS category,
    CASE
      WHEN lower(coalesce(item->>'is_veg', '')) IN ('true', '1', 'yes') THEN true
      WHEN lower(coalesce(item->>'is_veg', '')) IN ('false', '0', 'no') THEN false
      ELSE NULL
    END AS is_veg,
    item->>'hosting_address' AS hosting_address,
    item->>'fssai_number' AS fssai_number
  FROM lines
  WHERE coalesce(NULLIF(item->>'price', '')::numeric, 0) > 0
    AND coalesce(item->>'id', item->>'meal_id', item->>'source_meal_id', item->>'mealId') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
),
ranked AS (
  SELECT DISTINCT ON (meal_id) *
  FROM normalized
  WHERE meal_id IS NOT NULL
    AND title IS NOT NULL
    AND chef_id IS NOT NULL
  ORDER BY meal_id, ordered_at ASC
)
INSERT INTO public.meals (
  id,
  chef_id,
  title,
  price,
  is_veg,
  image_url,
  quantity,
  time_slot,
  status,
  category,
  description,
  chef_name,
  service_type,
  hosting_address,
  fssai_number,
  pickup_lat,
  pickup_lng,
  latitude,
  longitude,
  created_at,
  updated_at
)
SELECT
  r.meal_id,
  r.chef_id,
  r.title,
  r.price,
  coalesce(r.is_veg, m.is_veg, true),
  coalesce(nullif(r.image_url, ''), m.image_url),
  r.quantity,
  coalesce(r.time_slot, m.time_slot),
  coalesce(m.status, 'Available'),
  coalesce(nullif(r.category, ''), m.category, 'Maharashtrian'),
  coalesce(nullif(r.description, ''), m.description),
  coalesce(nullif(r.chef_name, ''), m.chef_name, u.full_name, u.name),
  r.service_type,
  coalesce(nullif(r.hosting_address, ''), m.hosting_address, nullif(u.address, '')),
  coalesce(nullif(r.fssai_number, ''), m.fssai_number, nullif(u.fssai_number, '')),
  coalesce(m.pickup_lat, u.lat, u.latitude),
  coalesce(m.pickup_lng, u.lng, u.longitude),
  coalesce(m.latitude, u.lat, u.latitude),
  coalesce(m.longitude, u.lng, u.longitude),
  least(r.ordered_at, coalesce(m.created_at, r.ordered_at)),
  now()
FROM ranked r
JOIN public.users u ON u.id = r.chef_id
LEFT JOIN public.meals m ON m.id = r.meal_id
ON CONFLICT (id) DO UPDATE SET
  title = EXCLUDED.title,
  price = EXCLUDED.price,
  time_slot = COALESCE(EXCLUDED.time_slot, public.meals.time_slot),
  image_url = COALESCE(EXCLUDED.image_url, public.meals.image_url),
  description = COALESCE(EXCLUDED.description, public.meals.description),
  is_veg = COALESCE(EXCLUDED.is_veg, public.meals.is_veg),
  updated_at = now();

DELETE FROM public.meals
WHERE coalesce(price, 0) <= 0;
