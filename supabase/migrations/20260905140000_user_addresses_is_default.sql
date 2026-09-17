-- Account "star" and checkout Home pin persist is_default on user_addresses.
-- The live table never had that column, so the star failed with PGRST204.

ALTER TABLE public.user_addresses
  ADD COLUMN IF NOT EXISTS is_default boolean NOT NULL DEFAULT false;

UPDATE public.user_addresses ua
SET is_default = true
WHERE ua.id IN (
  SELECT DISTINCT ON (user_id) id
  FROM public.user_addresses
  ORDER BY user_id, updated_at DESC NULLS LAST, created_at DESC NULLS LAST
)
AND NOT EXISTS (
  SELECT 1
  FROM public.user_addresses other
  WHERE other.user_id = ua.user_id
    AND other.is_default
);

NOTIFY pgrst, 'reload schema';
