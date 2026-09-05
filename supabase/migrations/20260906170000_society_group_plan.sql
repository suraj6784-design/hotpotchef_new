-- Society / office group carts: named place + shared slot note on the room.

ALTER TABLE public.shared_carts
  ADD COLUMN IF NOT EXISTS place_kind text NOT NULL DEFAULT 'friends',
  ADD COLUMN IF NOT EXISTS place_label text,
  ADD COLUMN IF NOT EXISTS dropoff_note text,
  ADD COLUMN IF NOT EXISTS time_slot text,
  ADD COLUMN IF NOT EXISTS selected_date text;

ALTER TABLE public.shared_carts
  DROP CONSTRAINT IF EXISTS shared_carts_place_kind_check;

ALTER TABLE public.shared_carts
  ADD CONSTRAINT shared_carts_place_kind_check
  CHECK (place_kind IN ('society', 'office', 'friends'));

NOTIFY pgrst, 'reload schema';
