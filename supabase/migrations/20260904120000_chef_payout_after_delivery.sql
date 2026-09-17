-- Chef payout is created only after delivery. Cancelled orders stay not_applicable.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS chef_payout numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS platform_margin numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS payout_status text DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS razorpay_transfer_id text,
  ADD COLUMN IF NOT EXISTS payout_released_at timestamptz;

COMMENT ON COLUMN public.orders.chef_payout IS 'Food + packaging after platform margin. Paid only after delivery.';
COMMENT ON COLUMN public.orders.platform_margin IS 'Platform share of food + packaging. Delivery fee is separate.';
COMMENT ON COLUMN public.orders.payout_status IS 'pending | processing | released | failed | awaiting_account | recorded | not_applicable';
