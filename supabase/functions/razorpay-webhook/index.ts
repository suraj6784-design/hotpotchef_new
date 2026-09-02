import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { jsonResponse } from '../_shared/cors.ts'
import { fetchPayment, hmacSha256Hex, refundPayment } from '../_shared/razorpay.ts'

serve(async (req) => {
  try {
    const secret = Deno.env.get('RAZORPAY_WEBHOOK_SECRET') ?? ''
    if (!secret) {
      return jsonResponse({ error: 'Webhook secret is not configured' }, 500)
    }

    const rawBody = await req.text()
    const signature = req.headers.get('x-razorpay-signature') ?? ''
    const expected = await hmacSha256Hex(rawBody, secret)
    if (!signature || expected !== signature) {
      return jsonResponse({ error: 'Invalid webhook signature' }, 400)
    }

    const payload = JSON.parse(rawBody)
    const event = payload?.event
    if (event !== 'payment.captured') {
      return jsonResponse({ skipped: true, event })
    }

    const paymentEntity = payload?.payload?.payment?.entity
    const paymentId = paymentEntity?.id as string | undefined
    const razorpayOrderId = paymentEntity?.order_id as string | undefined
    if (!paymentId || !razorpayOrderId) {
      return jsonResponse({ skipped: true, reason: 'missing payment ids' })
    }

    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    const { data: existing } = await admin.from('orders').select('id').eq('payment_id', paymentId).maybeSingle()
    if (existing?.id) {
      return jsonResponse({ success: true, already_recorded: true, order_id: existing.id })
    }

    const { data: pending } = await admin
      .from('pending_checkouts')
      .select('*')
      .eq('razorpay_order_id', razorpayOrderId)
      .maybeSingle()

    if (!pending) {
      return jsonResponse({ skipped: true, reason: 'no pending checkout' })
    }

    const { data: placed, error } = await admin.rpc('place_customer_order', {
      p_customer_email: pending.email,
      p_customer_phone: pending.phone,
      p_delivery_address: pending.delivery_address,
      p_instructions: pending.instructions,
      p_cart_items: pending.cart_items,
      p_apply_coins: pending.apply_coins,
      p_idempotency_key: paymentId,
      p_user_id: pending.user_id,
      p_tip_amount: pending.tip_amount,
      p_delivery_fee: pending.delivery_fee,
      p_payment_id: paymentId,
      p_razorpay_order_id: razorpayOrderId,
      p_razorpay_signature: null,
    })

    if (!error && placed?.success === true) {
      return jsonResponse({ success: true, order_id: placed.order_id })
    }

    try {
      const payment = await fetchPayment(paymentId)
      if (payment.status === 'captured') {
        await refundPayment(paymentId)
      }
      return jsonResponse({
        success: false,
        refunded: true,
        error: placed?.error || error?.message || 'Order could not be recorded',
      })
    } catch (refundErr) {
      return jsonResponse({
        success: false,
        refunded: false,
        error: refundErr.message,
      }, 500)
    }
  } catch (err) {
    return jsonResponse({ error: err.message ?? 'Webhook failed' }, 400)
  }
})
