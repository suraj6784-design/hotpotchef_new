-- Festival gift hampers chefs can list for Diwali / festive drops.

ALTER TABLE public.meals
  ADD COLUMN IF NOT EXISTS is_hamper boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS meals_hamper_available_idx
  ON public.meals (status, is_hamper)
  WHERE is_hamper = true;

NOTIFY pgrst, 'reload schema';
