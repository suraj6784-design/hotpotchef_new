-- Shelf / pantry from home kitchens (pickle, masala, papad).

ALTER TABLE public.meals
  ADD COLUMN IF NOT EXISTS is_shelf_item boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS shelf_kind text NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS meals_shelf_item_available_idx
  ON public.meals (status, is_shelf_item)
  WHERE is_shelf_item = true;

NOTIFY pgrst, 'reload schema';
