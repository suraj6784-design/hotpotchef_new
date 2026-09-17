-- Allow platform_ops members (in-app admin) to review brand referrals / go-live ads.
-- Keeps service_role path; adds is_platform_ops() path for HotPotChef ops desk.

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
  IF auth.role() IS DISTINCT FROM 'service_role' AND NOT public.is_platform_ops() THEN
    RAISE EXCEPTION 'Only HotPotChef platform ops may publish or price ad campaigns';
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
) TO authenticated, service_role;

-- Ops can read the full referral queue (chefs still only see their own via existing policy).
DROP POLICY IF EXISTS ad_campaigns_select_ops ON public.ad_campaigns;
CREATE POLICY ad_campaigns_select_ops ON public.ad_campaigns
  FOR SELECT
  TO authenticated
  USING (public.is_platform_ops());

-- Make suraj6784@gmail.com the sole platform ops admin (same UID after Customer→Chef flip).
DELETE FROM public.platform_ops
WHERE user_id NOT IN (
  SELECT id FROM auth.users WHERE lower(email) = lower('suraj6784@gmail.com')
);

INSERT INTO public.platform_ops (user_id, note)
SELECT id, 'exclusive HotPotChef platform admin'
FROM auth.users
WHERE lower(email) = lower('suraj6784@gmail.com')
ON CONFLICT (user_id) DO UPDATE
SET note = EXCLUDED.note;

NOTIFY pgrst, 'reload schema';
