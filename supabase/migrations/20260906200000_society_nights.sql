-- RWA / society night drops: one building, one chef, one slot.

ALTER TABLE public.meals
  ADD COLUMN IF NOT EXISTS is_society_night boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS society_label text NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS meals_society_night_available_idx
  ON public.meals (status, is_society_night)
  WHERE is_society_night = true;

NOTIFY pgrst, 'reload schema';
