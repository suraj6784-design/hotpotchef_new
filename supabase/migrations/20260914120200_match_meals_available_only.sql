-- Vector search must not return Archived / Closed / paused / cancelled meals.
-- Replaces the live match_meals body (SETOF meals, no status filter) without
-- changing the argument list so ai-search / ai-craving-matcher keep working.

CREATE OR REPLACE FUNCTION public.match_meals(
  query_embedding vector(768),
  match_threshold double precision DEFAULT 0.3,
  match_count integer DEFAULT 10
)
RETURNS SETOF public.meals
LANGUAGE sql
STABLE
AS $$
  SELECT m.*
  FROM public.meals m
  WHERE m.embedding IS NOT NULL
    AND lower(COALESCE(m.status, '')) = 'available'
    AND COALESCE(m.customer_name, '') = ''
    AND (1 - (m.embedding <=> query_embedding)) > match_threshold
  ORDER BY m.embedding <=> query_embedding
  LIMIT GREATEST(1, LEAST(COALESCE(match_count, 10), 50));
$$;

REVOKE ALL ON FUNCTION public.match_meals(vector, double precision, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.match_meals(vector, double precision, integer)
  TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
