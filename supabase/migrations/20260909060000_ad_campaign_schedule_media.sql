-- Brand ads: day-parting, campaign end, and short video clips. Ops can edit live creatives.

ALTER TABLE public.ad_campaigns
  ADD COLUMN IF NOT EXISTS video_url text,
  ADD COLUMN IF NOT EXISTS daily_start_minute integer,
  ADD COLUMN IF NOT EXISTS daily_end_minute integer,
  ADD COLUMN IF NOT EXISTS clip_duration_seconds integer;

ALTER TABLE public.ad_campaigns
  DROP CONSTRAINT IF EXISTS ad_campaigns_daily_start_minute_check;
ALTER TABLE public.ad_campaigns
  ADD CONSTRAINT ad_campaigns_daily_start_minute_check
  CHECK (daily_start_minute IS NULL OR (daily_start_minute >= 0 AND daily_start_minute < 1440));

ALTER TABLE public.ad_campaigns
  DROP CONSTRAINT IF EXISTS ad_campaigns_daily_end_minute_check;
ALTER TABLE public.ad_campaigns
  ADD CONSTRAINT ad_campaigns_daily_end_minute_check
  CHECK (daily_end_minute IS NULL OR (daily_end_minute >= 0 AND daily_end_minute <= 1440));

ALTER TABLE public.ad_campaigns
  DROP CONSTRAINT IF EXISTS ad_campaigns_clip_duration_seconds_check;
ALTER TABLE public.ad_campaigns
  ADD CONSTRAINT ad_campaigns_clip_duration_seconds_check
  CHECK (clip_duration_seconds IS NULL OR (clip_duration_seconds > 0 AND clip_duration_seconds <= 60));

COMMENT ON COLUMN public.ad_campaigns.daily_start_minute IS
  'Local minutes from midnight when the card may show. NULL = all day.';
COMMENT ON COLUMN public.ad_campaigns.daily_end_minute IS
  'Local minutes from midnight when the card stops (exclusive). NULL = all day. May wrap past midnight.';
COMMENT ON COLUMN public.ad_campaigns.video_url IS
  'Optional short looping clip for diner Home (keep under ~15 MB / 30s).';

INSERT INTO storage.buckets (id, name, public)
VALUES ('ad_campaigns', 'ad_campaigns', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS ad_campaigns_storage_public_read ON storage.objects;
CREATE POLICY ad_campaigns_storage_public_read
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'ad_campaigns');

DROP POLICY IF EXISTS ad_campaigns_storage_ops_write ON storage.objects;
CREATE POLICY ad_campaigns_storage_ops_write
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'ad_campaigns'
    AND public.is_platform_ops()
  );

DROP POLICY IF EXISTS ad_campaigns_storage_ops_update ON storage.objects;
CREATE POLICY ad_campaigns_storage_ops_update
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'ad_campaigns' AND public.is_platform_ops())
  WITH CHECK (bucket_id = 'ad_campaigns' AND public.is_platform_ops());

CREATE OR REPLACE FUNCTION public.platform_update_ad_campaign(
  p_campaign_id uuid,
  p_cta_url text DEFAULT NULL,
  p_cta_label text DEFAULT NULL,
  p_image_url text DEFAULT NULL,
  p_video_url text DEFAULT NULL,
  p_starts_at timestamptz DEFAULT NULL,
  p_ends_at timestamptz DEFAULT NULL,
  p_daily_start_minute integer DEFAULT NULL,
  p_daily_end_minute integer DEFAULT NULL,
  p_clip_duration_seconds integer DEFAULT NULL,
  p_title text DEFAULT NULL,
  p_body text DEFAULT NULL,
  p_clear_ends_at boolean DEFAULT false,
  p_clear_daypart boolean DEFAULT false,
  p_clear_video boolean DEFAULT false
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' AND NOT public.is_platform_ops() THEN
    RAISE EXCEPTION 'Only HotPotChef platform ops may edit ad campaigns';
  END IF;

  UPDATE public.ad_campaigns
  SET
    cta_url = COALESCE(p_cta_url, cta_url),
    cta_label = COALESCE(NULLIF(trim(p_cta_label), ''), cta_label),
    image_url = COALESCE(p_image_url, image_url),
    video_url = CASE WHEN p_clear_video THEN NULL ELSE COALESCE(p_video_url, video_url) END,
    starts_at = COALESCE(p_starts_at, starts_at),
    ends_at = CASE WHEN p_clear_ends_at THEN NULL ELSE COALESCE(p_ends_at, ends_at) END,
    daily_start_minute = CASE WHEN p_clear_daypart THEN NULL ELSE COALESCE(p_daily_start_minute, daily_start_minute) END,
    daily_end_minute = CASE WHEN p_clear_daypart THEN NULL ELSE COALESCE(p_daily_end_minute, daily_end_minute) END,
    clip_duration_seconds = COALESCE(p_clip_duration_seconds, clip_duration_seconds),
    title = COALESCE(NULLIF(trim(p_title), ''), title),
    body = COALESCE(p_body, body),
    updated_at = now()
  WHERE id = p_campaign_id;

  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.platform_update_ad_campaign(
  uuid, text, text, text, text, timestamptz, timestamptz, integer, integer, integer, text, text, boolean, boolean, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_update_ad_campaign(
  uuid, text, text, text, text, timestamptz, timestamptz, integer, integer, integer, text, text, boolean, boolean, boolean
) TO authenticated, service_role;

-- Existing Tada Salt row used a host without a scheme, so Learn more could not launch.
UPDATE public.ad_campaigns
SET cta_url = 'https://www.hotpotchef.com'
WHERE cta_url IS NOT NULL
  AND cta_url !~* '^https?://'
  AND lower(cta_url) LIKE '%hotpotchef.com%';

NOTIFY pgrst, 'reload schema';
