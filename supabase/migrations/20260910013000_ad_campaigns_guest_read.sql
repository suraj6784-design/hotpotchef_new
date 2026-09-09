-- Live brand placements are public Home inventory, including guests.

GRANT SELECT ON public.ad_campaigns TO anon, authenticated;

DROP POLICY IF EXISTS ad_campaigns_select_anon ON public.ad_campaigns;
CREATE POLICY ad_campaigns_select_anon ON public.ad_campaigns
  FOR SELECT
  TO anon
  USING (
    status = 'live'
    AND (starts_at IS NULL OR starts_at <= now())
    AND (ends_at IS NULL OR ends_at >= now())
  );

NOTIFY pgrst, 'reload schema';
