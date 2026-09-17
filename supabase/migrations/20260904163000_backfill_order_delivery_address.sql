-- Older orders were placed before orders.delivery_address existed, so My Orders
-- showed "Unknown Location". Copy the customer's latest saved address onto those rows.

UPDATE public.orders o
SET delivery_address = src.formatted
FROM (
  SELECT DISTINCT ON (ua.user_id)
    ua.user_id,
    NULLIF(
      trim(both FROM concat_ws(', ',
        NULLIF(btrim(ua.house_no), ''),
        NULLIF(btrim(COALESCE(ua.street, ua.address_line1)), ''),
        NULLIF(btrim(ua.landmark), ''),
        NULLIF(btrim(ua.city), ''),
        NULLIF(btrim(ua.state), '')
      ) || COALESCE(' - ' || NULLIF(btrim(ua.postal_code), ''), '')),
      ''
    ) AS formatted
  FROM public.user_addresses ua
  ORDER BY ua.user_id, ua.updated_at DESC NULLS LAST, ua.created_at DESC NULLS LAST
) src
WHERE o.customer_id = src.user_id
  AND COALESCE(btrim(o.delivery_address), '') = ''
  AND src.formatted IS NOT NULL;

UPDATE public.orders o
SET delivery_address = btrim(u.address)
FROM public.users u
WHERE o.customer_id = u.id
  AND COALESCE(btrim(o.delivery_address), '') = ''
  AND NULLIF(btrim(u.address), '') IS NOT NULL;

NOTIFY pgrst, 'reload schema';
