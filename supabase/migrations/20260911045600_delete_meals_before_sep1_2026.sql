-- Remove catalog dishes created before 1 Sep 2026 (IST).
-- Order receipts keep their own item JSON; meal_boosts cascade.

DELETE FROM public.meals
WHERE created_at < timestamptz '2026-09-01 00:00:00+05:30';
