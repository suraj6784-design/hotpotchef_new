import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { jsonResponse, optionsResponse } from '../_shared/cors.ts'
import { refundPayment } from '../_shared/razorpay.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') return optionsResponse()

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return jsonResponse({ success: false, error: 'Unauthorized' }, 401)

    const body = await req.json()
    const orderId = String(body.order_id ?? '')
    const reason = String(body.reason ?? 'Cancelled')
    const chefId = body.chef_id ? String(body.chef_id) : null
    if (!orderId) return jsonResponse({ success: false, error: 'order_id is required' }, 400)

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: userData, error: userError } = await userClient.auth.getUser()
    if (userError || !userData.user) {
      return jsonResponse({ success: false, error: 'Unauthorized' }, 401)
    }

    const { data: cancelled, error: cancelError } = await userClient.rpc('cancel_and_restock_order', {
      p_order_id: orderId,
      p_reason: reason,
      p_chef_id: chefId,
    })
    if (cancelError) throw new Error(cancelError.message)
    if (!cancelled || cancelled.success !== true) {
      return jsonResponse({
        success: false,
        error: cancelled?.error || 'Cancellation rejected',
      }, 400)
    }

    const paymentId = cancelled.payment_id as string | null
    const alreadyRefunded = ['processed', 'refunded', 'already_refunded'].includes(
      String(cancelled.refund_status || '').toLowerCase(),
    )

    let refundId = cancelled.refund_id as string | null
    let refundStatus = cancelled.refund_status as string | null
    if (paymentId && !alreadyRefunded) {
      try {
        const refund = await refundPayment(paymentId)
        refundId = refund?.id ?? refundId
        refundStatus = refund?.status ?? 'processed'
        const admin = createClient(supabaseUrl, serviceKey)
        await admin.from('orders').update({
          refund_id: refundId,
          refund_status: refundStatus,
          updated_at: new Date().toISOString(),
        }).eq('id', orderId)
      } catch (refundErr) {
        const admin = createClient(supabaseUrl, serviceKey)
        await admin.from('orders').update({
          refund_status: 'failed',
          updated_at: new Date().toISOString(),
        }).eq('id', orderId)
        return jsonResponse({
          success: true,
          restocked: true,
          refunded: false,
          error: refundErr.message,
          message: 'Order cancelled and stock restored. Refund is pending — we will retry shortly.',
        })
      }
    }

    return jsonResponse({
      success: true,
      restocked: true,
      refunded: Boolean(paymentId) && refundStatus !== 'failed',
      refund_id: refundId,
    })
  } catch (err) {
    return jsonResponse({ success: false, error: err.message ?? 'Cancel failed' }, 400)
  }
})
