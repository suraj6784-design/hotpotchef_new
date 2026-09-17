-- Cloud-synced Kitchen Academy progress + completion certificate.

CREATE TABLE IF NOT EXISTS public.chef_academy_progress (
  user_id uuid PRIMARY KEY REFERENCES public.users (id) ON DELETE CASCADE,
  completed_lessons text[] NOT NULL DEFAULT '{}',
  passed_quizzes text[] NOT NULL DEFAULT '{}',
  certificate_code text,
  certificate_issued_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS chef_academy_progress_issued_idx
  ON public.chef_academy_progress (certificate_issued_at)
  WHERE certificate_issued_at IS NOT NULL;

ALTER TABLE public.chef_academy_progress ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON public.chef_academy_progress TO authenticated;
GRANT ALL ON public.chef_academy_progress TO service_role;

DROP POLICY IF EXISTS chef_academy_progress_select ON public.chef_academy_progress;
CREATE POLICY chef_academy_progress_select ON public.chef_academy_progress
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS chef_academy_progress_insert ON public.chef_academy_progress;
CREATE POLICY chef_academy_progress_insert ON public.chef_academy_progress
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS chef_academy_progress_update ON public.chef_academy_progress;
CREATE POLICY chef_academy_progress_update ON public.chef_academy_progress
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

NOTIFY pgrst, 'reload schema';
