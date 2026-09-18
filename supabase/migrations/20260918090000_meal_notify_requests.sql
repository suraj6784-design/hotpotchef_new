-- Diner "notify me when available" requests for a plate.

CREATE TABLE IF NOT EXISTS public.meal_notify_requests (
  diner_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  meal_id uuid NOT NULL REFERENCES public.meals(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (diner_id, meal_id)
);

CREATE INDEX IF NOT EXISTS meal_notify_requests_meal_id_idx
  ON public.meal_notify_requests (meal_id);

ALTER TABLE public.meal_notify_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS meal_notify_requests_select_own ON public.meal_notify_requests;
CREATE POLICY meal_notify_requests_select_own
  ON public.meal_notify_requests
  FOR SELECT
  TO authenticated
  USING (diner_id = auth.uid());

DROP POLICY IF EXISTS meal_notify_requests_insert_own ON public.meal_notify_requests;
CREATE POLICY meal_notify_requests_insert_own
  ON public.meal_notify_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (diner_id = auth.uid());

DROP POLICY IF EXISTS meal_notify_requests_delete_own ON public.meal_notify_requests;
CREATE POLICY meal_notify_requests_delete_own
  ON public.meal_notify_requests
  FOR DELETE
  TO authenticated
  USING (diner_id = auth.uid());

GRANT SELECT, INSERT, DELETE ON public.meal_notify_requests TO authenticated;

NOTIFY pgrst, 'reload schema';
