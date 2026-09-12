-- Keep meals published before 1 Sep 2026 (IST).
-- Remove only ₹0-priced plates from that window. Paid catalog stays.
-- Order receipts keep their own item JSON; meal_boosts cascade.

DELETE FROM public.meals
WHERE created_at < timestamptz '2026-09-01 00:00:00+05:30'
  AND coalesce(price, 0) <= 0;
