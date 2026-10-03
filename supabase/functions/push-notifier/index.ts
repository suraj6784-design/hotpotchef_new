import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { jsonResponse, optionsResponse } from '../_shared/cors.ts'
import { adminClient, isServiceRoleRequest, jsonUnauthorized } from '../_shared/guard.ts'
import { dispatchOrderAlert } from '../_shared/alerts.ts'
import { authorizeInternalInvoke } from '../_shared/webhook_auth.ts'

// Working FCM fallback if send-push-notification fails to boot. Anon/publishable
// JWT is not enough — handler returns 401 Unauthorized (X-Webhook-Secret or service_role).

serve(async (req) => {
  if (req.method === 'OPTIONS') return optionsResponse()

  try {
    const internal = authorizeInternalInvoke(req.headers)
    if (!internal.ok && !isServiceRoleRequest(req)) return jsonUnauthorized()

    const payload = await req.json()
    const newRecord = payload.record
    const oldRecord = payload.old_record
    if (oldRecord && newRecord?.status === oldRecord.status) {
      return jsonResponse({ message: 'Status unchanged, ignoring.' })
    }
    const orderId = String(newRecord?.id ?? '')
    if (!orderId) return jsonResponse({ success: false, error: 'id is required' }, 400)

    const admin = adminClient()
    const result = await dispatchOrderAlert(admin, orderId, {
      isInsert: !oldRecord,
      previousStatus: oldRecord?.status ?? null,
    })
    return jsonResponse({ success: true, ...result })
  } catch (err) {
    return jsonResponse({ success: false, error: err?.message ?? String(err) }, 500)
  }
})
