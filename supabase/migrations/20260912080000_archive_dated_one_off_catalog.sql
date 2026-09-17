-- Keep priced plates, but take dated one-off slots off Home.
-- Chef History still lists Archived rows. Recurring Daily/weekday windows stay live.

UPDATE public.meals
SET
  status = 'Archived',
  updated_at = now()
WHERE lower(btrim(coalesce(status, ''))) IN ('available', 'paused')
  AND coalesce(price, 0) > 0
  AND time_slot ~* '\d{1,2}(st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)'
  AND time_slot !~* '\bdaily\b';
