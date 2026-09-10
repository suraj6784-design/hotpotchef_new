-- Archive leftover plates that do not meet current publish rules
-- (₹0 price, Flexible/ASAP slot, no clock hours, no service, no kitchen pin/address).

UPDATE public.meals
SET status = 'Archived'
WHERE lower(btrim(coalesce(status, ''))) NOT IN ('archived', 'deleted')
  AND (
    coalesce(price, 0) <= 0
    OR nullif(btrim(coalesce(title, '')), '') IS NULL
    OR nullif(btrim(coalesce(time_slot, '')), '') IS NULL
    OR lower(btrim(time_slot)) IN ('flexible', 'asap', 'now')
    OR lower(time_slot) LIKE '%flexible%'
    OR (
      lower(time_slot) LIKE '%asap%'
      AND time_slot !~* '[0-9]{1,2}:[0-9]{2}'
    )
    OR time_slot !~* '[0-9]{1,2}:[0-9]{2}'
    OR nullif(btrim(coalesce(service_type, '')), '') IS NULL
    OR pickup_lat IS NULL
    OR pickup_lng IS NULL
    OR nullif(btrim(coalesce(hosting_address, '')), '') IS NULL
  );
