-- Group-order rooms used by SharedCartService, plus optional extras on meals.

CREATE TABLE IF NOT EXISTS public.shared_carts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_code text NOT NULL UNIQUE,
  host_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  items jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS shared_carts_host_idx
  ON public.shared_carts (host_id, updated_at DESC);

ALTER TABLE public.shared_carts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS shared_carts_select ON public.shared_carts;
CREATE POLICY shared_carts_select ON public.shared_carts
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS shared_carts_insert ON public.shared_carts;
CREATE POLICY shared_carts_insert ON public.shared_carts
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = host_id);

DROP POLICY IF EXISTS shared_carts_update ON public.shared_carts;
CREATE POLICY shared_carts_update ON public.shared_carts
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS shared_carts_delete ON public.shared_carts;
CREATE POLICY shared_carts_delete ON public.shared_carts
  FOR DELETE
  TO authenticated
  USING (auth.uid() = host_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.shared_carts TO authenticated;
GRANT ALL ON public.shared_carts TO service_role;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.shared_carts;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;

ALTER TABLE IF EXISTS public.meals
  ADD COLUMN IF NOT EXISTS add_ons jsonb NOT NULL DEFAULT '[]'::jsonb;

NOTIFY pgrst, 'reload schema';
