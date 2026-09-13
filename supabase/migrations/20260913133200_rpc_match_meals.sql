-- Vector similarity search used by supabase/functions/ai-search and
-- supabase/functions/ai-craving-matcher.
--
-- Call site:
--   match_meals(query_embedding, match_threshold, match_count)
-- Gemini text-embedding-004 produces 768-d vectors.
--
-- No SQL for this RPC exists in repo history. Return shape is meal catalog
-- columns plus `similarity` so edge functions can JSON-serialize the rows
-- as `meals`.
--
-- reconstructed from call sites — verify against hosted project before production
--
-- Embeddings are not written by the current Flutter/edge code. Until a
-- backfill (or ai-tag-meal) populates meals.embedding, this RPC returns [].
-- ai-search already falls back to title/description ILIKE.

CREATE OR REPLACE FUNCTION public.match_meals(
  query_embedding vector(768),
  match_threshold double precision DEFAULT 0.3,
  match_count integer DEFAULT 10
)
RETURNS TABLE (
  id uuid,
  chef_id uuid,
  chef_name text,
  title text,
  name text,
  description text,
  price numeric,
  discounted_price numeric,
  quantity integer,
  category text,
  is_veg boolean,
  time_slot text,
  service_type text,
  image_url text,
  status text,
  health_tags jsonb,
  offer_type text,
  discount_value numeric,
  fssai_number text,
  hosting_address text,
  pickup_lat numeric,
  pickup_lng numeric,
  accepts_hotpot_coins boolean,
  similarity double precision
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    m.id,
    m.chef_id,
    m.chef_name,
    m.title,
    m.name,
    m.description,
    m.price,
    m.discounted_price,
    m.quantity,
    m.category,
    m.is_veg,
    m.time_slot,
    m.service_type,
    m.image_url,
    m.status,
    m.health_tags,
    m.offer_type,
    m.discount_value,
    m.fssai_number,
    m.hosting_address,
    m.pickup_lat,
    m.pickup_lng,
    m.accepts_hotpot_coins,
    (1 - (m.embedding <=> query_embedding))::double precision AS similarity
  FROM public.meals m
  WHERE m.embedding IS NOT NULL
    AND coalesce(m.customer_name, '') = ''
    AND lower(coalesce(m.status, '')) NOT IN ('paused', 'sold out', 'cancelled')
    AND (1 - (m.embedding <=> query_embedding)) >= match_threshold
  ORDER BY m.embedding <=> query_embedding
  LIMIT GREATEST(1, LEAST(COALESCE(match_count, 10), 50));
$$;

REVOKE ALL ON FUNCTION public.match_meals(vector, double precision, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.match_meals(vector, double precision, integer) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
