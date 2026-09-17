-- Broadcast Bulk Pre-Order writes latitude/longitude and remaining_quantity.
-- Live customer_requests was created without those columns (PGRST204).

DO $$
BEGIN
  IF to_regclass('public.customer_requests') IS NULL THEN
    RAISE NOTICE 'customer_requests missing; skip geo columns';
    RETURN;
  END IF;

  ALTER TABLE public.customer_requests
    ADD COLUMN IF NOT EXISTS latitude double precision;
  ALTER TABLE public.customer_requests
    ADD COLUMN IF NOT EXISTS longitude double precision;
  ALTER TABLE public.customer_requests
    ADD COLUMN IF NOT EXISTS remaining_quantity integer;

  UPDATE public.customer_requests
  SET remaining_quantity = quantity
  WHERE remaining_quantity IS NULL
    AND quantity IS NOT NULL;
END $$;

NOTIFY pgrst, 'reload schema';
