import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { jsonResponse, optionsResponse } from '../_shared/cors.ts'
import { adminClient, isServiceRoleRequest, jsonUnauthorized, requireUser } from '../_shared/guard.ts'
import { dispatchChatAlert, dispatchKitchenLiveAlert, dispatchOrderAlert, dispatchUserNotification, dispatchWelcome } from '../_shared/alerts.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') return optionsResponse()

  try {
    let callerId: string | null = null
    if (isServiceRoleRequest(req)) {
      callerId = null
    } else {
      const auth = await requireUser(req)
      if (auth instanceof Response) return auth
      callerId = auth.user.id
    }

    const payload = await req.json()
    const table = String(payload.table ?? '')
    const type = String(payload.type ?? payload.event ?? '').toUpperCase()
    const record = payload.record ?? payload
    const oldRecord = payload.old_record ?? payload.oldRecord ?? null
    const id = String(record?.id ?? payload.order_id ?? payload.message_id ?? payload.user_id ?? '')
    const admin = adminClient()

    if (payload.event === 'welcome') {
      const requested = String(payload.user_id ?? record?.user_id ?? id)
      const userId = callerId ?? requested
      if (!userId) return jsonResponse({ success: false, error: 'user_id is required' }, 400)
      if (callerId && callerId !== userId) return jsonUnauthorized('You can only send your own welcome')
      const result = await dispatchWelcome(admin, userId)
      return jsonResponse({ success: true, ...result })
    }

    if (!id) return jsonResponse({ success: false, error: 'id is required' }, 400)

    if (table === 'messages' || payload.event === 'chat') {
      if (callerId) {
        const { data: row } = await admin.from('messages').select('sender_id, user_id, customer_id, chef_id').eq('id', id).maybeSingle()
        const parties = [row?.sender_id, row?.user_id, row?.customer_id, row?.chef_id].map((v) => String(v ?? ''))
        if (!parties.includes(callerId)) return jsonUnauthorized()
      }
      const result = await dispatchChatAlert(admin, id)
      return jsonResponse({ success: true, ...result })
    }

    if (table === 'chef_profiles' || payload.event === 'kitchen_live') {
      const chefId = String(record?.user_id ?? record?.chef_id ?? id)
      if (callerId && callerId !== chefId) return jsonUnauthorized()
      const result = await dispatchKitchenLiveAlert(admin, chefId)
      return jsonResponse({ success: true, ...result })
    }

    if (table === 'user_notifications' || payload.event === 'kyc_reminder') {
      if (callerId) {
        const { data: row } = await admin.from('user_notifications').select('user_id').eq('id', id).maybeSingle()
        if (String(row?.user_id ?? '') !== callerId) return jsonUnauthorized()
      }
      const result = await dispatchUserNotification(admin, id)
      return jsonResponse({ success: true, ...result })
    }

    if (callerId) {
      const { data: order } = await admin
        .from('orders')
        .select('customer_id, chef_id, driver_id, delivery_partner_id')
        .eq('id', id)
        .maybeSingle()
      const parties = [
        order?.customer_id,
        order?.chef_id,
        order?.driver_id,
        order?.delivery_partner_id,
      ].map((v) => String(v ?? ''))
      if (!parties.includes(callerId)) return jsonUnauthorized()
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
