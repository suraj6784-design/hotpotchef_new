-- Third-party advertising scaffold: overall or targeted sponsored placements.

CREATE TABLE IF NOT EXISTS public.ad_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  advertiser_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  advertiser_name text,
  title text NOT NULL,
  body text,
  image_url text,
  cta_label text NOT NULL DEFAULT 'Learn more',
  cta_url text,
  reach_mode text NOT NULL DEFAULT 'overall'
    CHECK (reach_mode IN ('overall', 'targeted')),
  city text,
  radius_km numeric,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'live', 'ended')),
  starts_at timestamptz,
  ends_at timestamptz,
  package_label text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ad_campaigns_live_idx
  ON public.ad_campaigns (status, starts_at, ends_at);

CREATE INDEX IF NOT EXISTS ad_campaigns_advertiser_idx
  ON public.ad_campaigns (advertiser_id, updated_at DESC);

ALTER TABLE public.ad_campaigns ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.ad_campaigns TO authenticated;
GRANT ALL ON public.ad_campaigns TO service_role;

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
  WITH CHECK (advertiser_id = auth.uid());

DROP POLICY IF EXISTS ad_campaigns_update ON public.ad_campaigns;
CREATE POLICY ad_campaigns_update ON public.ad_campaigns
  FOR UPDATE
  TO authenticated
  USING (advertiser_id = auth.uid())
  WITH CHECK (advertiser_id = auth.uid());

DROP POLICY IF EXISTS ad_campaigns_delete ON public.ad_campaigns;
CREATE POLICY ad_campaigns_delete ON public.ad_campaigns
  FOR DELETE
  TO authenticated
  USING (advertiser_id = auth.uid());

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.ad_campaigns;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;

NOTIFY pgrst, 'reload schema';
