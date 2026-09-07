-- Platform owns commercial go-live for third-party ads.
-- Chefs may only refer brands (draft / pending_review). Only service_role may set live.

ALTER TABLE public.ad_campaigns
  ADD COLUMN IF NOT EXISTS source_role text NOT NULL DEFAULT 'chef_referral',
  ADD COLUMN IF NOT EXISTS contact_note text,
  ADD COLUMN IF NOT EXISTS package_amount_paise integer,
  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
  ADD COLUMN IF NOT EXISTS review_note text;

COMMENT ON COLUMN public.ad_campaigns.source_role IS
  'chef_referral | platform_sales | brand_portal — who opened the lead.';
COMMENT ON COLUMN public.ad_campaigns.package_amount_paise IS
  'Platform-set price in paise once commercial terms are agreed; null until priced.';

-- Expand status vocabulary for review queue.
DO $$
DECLARE
  cname text;
BEGIN
  SELECT con.conname INTO cname
  FROM pg_constraint con
  JOIN pg_class rel ON rel.oid = con.conrelid
  JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
  WHERE nsp.nspname = 'public'
    AND rel.relname = 'ad_campaigns'
    AND con.contype = 'c'
    AND pg_get_constraintdef(con.oid) ILIKE '%status%'
  ORDER BY con.conname
  FETCH FIRST 1 ROW ONLY;
  IF cname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.ad_campaigns DROP CONSTRAINT %I', cname);
  END IF;
END $$;

ALTER TABLE public.ad_campaigns
  ADD CONSTRAINT ad_campaigns_status_check
  CHECK (status IN ('draft', 'pending_review', 'live', 'ended'));

ALTER TABLE public.ad_campaigns
  DROP CONSTRAINT IF EXISTS ad_campaigns_source_role_check;
ALTER TABLE public.ad_campaigns
  ADD CONSTRAINT ad_campaigns_source_role_check
  CHECK (source_role IN ('chef_referral', 'platform_sales', 'brand_portal'));

-- Re-lock RLS: chefs never publish live placements.
DROP POLICY IF EXISTS ad_campaigns_select ON public.ad_campaigns;
CREATE POLICY ad_campaigns_select ON public.ad_campaigns
  FOR SELECT
  TO authenticated
  USING (
    advertiser_id = auth.uid()
    OR (
      status = 'live'
      AND (starts_at IS NULL OR starts_at <= now())
      AND (ends_at IS NULL OR ends_at >= now())
    )
  );

DROP POLICY IF EXISTS ad_campaigns_insert ON public.ad_campaigns;
CREATE POLICY ad_campaigns_insert ON public.ad_campaigns
  FOR INSERT
  TO authenticated
  WITH CHECK (
    advertiser_id = auth.uid()
    AND status IN ('draft', 'pending_review')
  );

DROP POLICY IF EXISTS ad_campaigns_update ON public.ad_campaigns;
CREATE POLICY ad_campaigns_update ON public.ad_campaigns
  FOR UPDATE
  TO authenticated
  USING (
    advertiser_id = auth.uid()
    AND status IN ('draft', 'pending_review')
  )
  WITH CHECK (
    advertiser_id = auth.uid()
    AND status IN ('draft', 'pending_review', 'ended')
  );

DROP POLICY IF EXISTS ad_campaigns_delete ON public.ad_campaigns;
CREATE POLICY ad_campaigns_delete ON public.ad_campaigns
  FOR DELETE
  TO authenticated
  USING (
    advertiser_id = auth.uid()
    AND status IN ('draft', 'pending_review')
  );

-- Platform go-live helper (service_role / dashboard SQL can also UPDATE directly).
CREATE OR REPLACE FUNCTION public.platform_set_ad_campaign_status(
  p_campaign_id uuid,
  p_status text,
  p_review_note text DEFAULT NULL,
  p_package_amount_paise integer DEFAULT NULL,
  p_package_label text DEFAULT NULL,
  p_starts_at timestamptz DEFAULT NULL,
  p_ends_at timestamptz DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Only the platform service role may publish or price ad campaigns';
  END IF;

  IF p_status NOT IN ('draft', 'pending_review', 'live', 'ended') THEN
    RAISE EXCEPTION 'Invalid campaign status';
  END IF;

  UPDATE public.ad_campaigns
  SET
    status = p_status,
    review_note = COALESCE(p_review_note, review_note),
    package_amount_paise = COALESCE(p_package_amount_paise, package_amount_paise),
    package_label = COALESCE(p_package_label, package_label),
    starts_at = COALESCE(p_starts_at, starts_at),
    ends_at = COALESCE(p_ends_at, ends_at),
    reviewed_at = CASE
      WHEN p_status IN ('live', 'ended', 'draft') THEN now()
      ELSE reviewed_at
    END,
    updated_at = now()
  WHERE id = p_campaign_id;

  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.platform_set_ad_campaign_status(
  uuid, text, text, integer, text, timestamptz, timestamptz
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_set_ad_campaign_status(
  uuid, text, text, integer, text, timestamptz, timestamptz
) TO service_role;

NOTIFY pgrst, 'reload schema';
