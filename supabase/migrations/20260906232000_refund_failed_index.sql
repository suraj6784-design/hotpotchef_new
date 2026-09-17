-- Help ops find stuck refunds quickly.
CREATE INDEX IF NOT EXISTS orders_refund_failed_idx
  ON public.orders (updated_at)
  WHERE lower(coalesce(refund_status, '')) = 'failed';

NOTIFY pgrst, 'reload schema';
