-- Drivers must not claim or see unassigned jobs until the kitchen is ready.
-- Pending / Confirmed / Preparing stay on the chef queue.

CREATE OR REPLACE FUNCTION public.is_open_driver_job(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    p_status IS NOT NULL
    AND p_status NOT ILIKE '%pending%'
    AND p_status NOT ILIKE '%confirm%'
    AND p_status NOT ILIKE '%prepar%'
    AND p_status NOT ILIKE '%delivered%'
    AND p_status NOT ILIKE '%cancelled%'
    AND p_status NOT ILIKE '%rejected%'
    AND p_status NOT ILIKE '%completed%'
    AND (
      p_status ILIKE '%ready%'
      OR p_status ILIKE '%assigned%'
      OR p_status ILIKE '%out for delivery%'
      OR p_status ILIKE '%out_for_delivery%'
    );
$$;

NOTIFY pgrst, 'reload schema';
