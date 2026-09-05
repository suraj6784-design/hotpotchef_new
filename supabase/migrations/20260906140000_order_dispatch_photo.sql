-- Packed-box photo the diner sees when the kitchen marks an order ready.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS dispatch_photo_url text,
  ADD COLUMN IF NOT EXISTS dispatch_photo_at timestamptz;

NOTIFY pgrst, 'reload schema';
