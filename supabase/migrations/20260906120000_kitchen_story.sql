-- Kitchen story, live flag, and ephemeral WebRTC signaling for kitchen streams.

ALTER TABLE public.chef_profiles
  ADD COLUMN IF NOT EXISTS kitchen_story text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS hygiene_note text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS kitchen_photos jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS live_photo_url text,
  ADD COLUMN IF NOT EXISTS live_photo_at timestamptz,
  ADD COLUMN IF NOT EXISTS is_live boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS live_started_at timestamptz;

CREATE TABLE IF NOT EXISTS public.kitchen_live_signals (
  id bigserial PRIMARY KEY,
  room_id uuid NOT NULL,
  sender_id text NOT NULL,
  target_id text,
  kind text NOT NULL,
  body jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS kitchen_live_signals_room_idx
  ON public.kitchen_live_signals (room_id, id);

ALTER TABLE public.kitchen_live_signals ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT ON public.kitchen_live_signals TO anon, authenticated;
GRANT DELETE ON public.kitchen_live_signals TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.kitchen_live_signals_id_seq TO anon, authenticated;
GRANT ALL ON public.kitchen_live_signals TO service_role;

DROP POLICY IF EXISTS kitchen_live_signals_select ON public.kitchen_live_signals;
CREATE POLICY kitchen_live_signals_select ON public.kitchen_live_signals
  FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS kitchen_live_signals_insert ON public.kitchen_live_signals;
CREATE POLICY kitchen_live_signals_insert ON public.kitchen_live_signals
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS kitchen_live_signals_delete ON public.kitchen_live_signals;
CREATE POLICY kitchen_live_signals_delete ON public.kitchen_live_signals
  FOR DELETE
  TO authenticated
  USING (auth.uid() = room_id OR auth.uid()::text = sender_id);

GRANT SELECT ON public.chef_profiles TO anon;
DROP POLICY IF EXISTS chef_profiles_select_anon ON public.chef_profiles;
CREATE POLICY chef_profiles_select_anon ON public.chef_profiles
  FOR SELECT
  TO anon
  USING (true);

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.kitchen_live_signals;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;

NOTIFY pgrst, 'reload schema';
