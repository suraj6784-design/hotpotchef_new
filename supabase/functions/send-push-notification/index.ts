import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { jsonResponse, optionsResponse } from '../_shared/cors.ts'
import { dispatchChatAlert, dispatchOrderAlert } from '../_shared/alerts.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') return optionsResponse()

  try {
    const payload = await req.json()
    const table = String(payload.table ?? '')
    const type = String(payload.type ?? payload.event ?? '').toUpperCase()
    const record = payload.record ?? payload
    const oldRecord = payload.old_record ?? payload.oldRecord ?? null
    const id = String(record?.id ?? payload.order_id ?? payload.message_id ?? '')

    if (!id) return jsonResponse({ success: false, error: 'id is required' }, 400)

    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    if (table === 'messages' || payload.event === 'chat') {
      const result = await dispatchChatAlert(admin, id)
      return jsonResponse({ success: true, ...result })
    }

    const isInsert = type === 'INSERT' || type === 'POST' || payload.event === 'order_placed'
    const result = await dispatchOrderAlert(admin, id, {
      isInsert,
      previousStatus: oldRecord?.status ?? null,
    })
    return jsonResponse({ success: true, ...result })
  } catch (err) {
    return jsonResponse({ success: false, error: err?.message ?? String(err) }, 500)
  }
})
