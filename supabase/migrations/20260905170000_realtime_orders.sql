-- My Orders stayed stale after checkout because orders was not in realtime.
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
