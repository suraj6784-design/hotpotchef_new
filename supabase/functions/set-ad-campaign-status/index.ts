import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { jsonResponse, optionsResponse } from '../_shared/cors.ts'

/**
 * Platform-only: approve / price / go-live / end third-party ad campaigns.
 * Call with the service role key (ops script or internal admin).
 */
serve(async (req) => {
  if (req.method === 'OPTIONS') return optionsResponse()

  try {
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const authHeader = req.headers.get('Authorization') ?? ''
    if (!serviceKey || authHeader !== `Bearer ${serviceKey}`) {
      return jsonResponse({ success: false, error: 'Platform service role required' }, 403)
    }

    const body = await req.json().catch(() => ({}))
    const campaignId = String(body.campaign_id ?? '').trim()
    const status = String(body.status ?? '').trim().toLowerCase()
    if (!campaignId) return jsonResponse({ success: false, error: 'campaign_id is required' }, 400)
    if (!['draft', 'pending_review', 'live', 'ended'].includes(status)) {
      return jsonResponse({ success: false, error: 'Invalid status' }, 400)
    }

    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      serviceKey,
    )

    const { data, error } = await admin.rpc('platform_set_ad_campaign_status', {
      p_campaign_id: campaignId,
      p_status: status,
      p_review_note: body.review_note ?? null,
      p_package_amount_paise:
        body.package_amount_paise == null ? null : Number(body.package_amount_paise),
      p_package_label: body.package_label ?? null,
      p_starts_at: body.starts_at ?? null,
      p_ends_at: body.ends_at ?? null,
    })

    if (error) throw new Error(error.message)
    if (data !== true) {
      return jsonResponse({ success: false, error: 'Campaign not found' }, 404)
    }

    return jsonResponse({ success: true, campaign_id: campaignId, status })
  } catch (err) {
    return jsonResponse({ success: false, error: err.message ?? 'Failed to update campaign' }, 400)
  }
})
