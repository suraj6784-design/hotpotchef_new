-- Diners follow a kitchen and get pinged when it goes back online.

CREATE TABLE IF NOT EXISTS public.kitchen_follows (
  customer_id uuid NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  chef_id uuid NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (customer_id, chef_id),
  CONSTRAINT kitchen_follows_not_self CHECK (customer_id <> chef_id)
);

CREATE INDEX IF NOT EXISTS kitchen_follows_chef_idx
  ON public.kitchen_follows (chef_id);

ALTER TABLE public.kitchen_follows ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, DELETE ON public.kitchen_follows TO authenticated;
GRANT ALL ON public.kitchen_follows TO service_role;

DROP POLICY IF EXISTS kitchen_follows_select ON public.kitchen_follows;
CREATE POLICY kitchen_follows_select ON public.kitchen_follows
  FOR SELECT
  TO authenticated
  USING (auth.uid() = customer_id OR auth.uid() = chef_id);

DROP POLICY IF EXISTS kitchen_follows_insert ON public.kitchen_follows;
CREATE POLICY kitchen_follows_insert ON public.kitchen_follows
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = customer_id AND customer_id <> chef_id);

DROP POLICY IF EXISTS kitchen_follows_delete ON public.kitchen_follows;
CREATE POLICY kitchen_follows_delete ON public.kitchen_follows
  FOR DELETE
  TO authenticated
  USING (auth.uid() = customer_id);

NOTIFY pgrst, 'reload schema';
