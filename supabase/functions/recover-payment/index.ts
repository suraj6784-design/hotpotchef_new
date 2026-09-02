import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { jsonResponse, optionsResponse } from '../_shared/cors.ts'
import { fetchPayment, refundPayment, verifyCheckoutSignature } from '../_shared/razorpay.ts'

type PendingCheckout = {
  user_id: string
  cart_items: unknown
  delivery_address: string | null
  instructions: string | null
  phone: string | null
  email: string | null
  apply_coins: boolean
  tip_amount: number
  delivery_fee: number
}

async function placeFromPending(
  admin: SupabaseClient,
  pending: PendingCheckout,
  paymentId: string,
  razorpayOrderId: string,
  signature: string | null,
) {
  return await admin.rpc('place_customer_order', {
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
    p_razorpay_signature: signature,
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return optionsResponse()

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return jsonResponse({ success: false, error: 'Unauthorized' }, 401)

    const body = await req.json()
    const paymentId = String(body.payment_id ?? '')
    const razorpayOrderId = String(body.razorpay_order_id ?? body.order_id ?? '')
    const signature = String(body.razorpay_signature ?? body.signature ?? '')

    if (!paymentId || !razorpayOrderId || !signature) {
      return jsonResponse({ success: false, error: 'Missing payment verification fields' }, 400)
    }

    const valid = await verifyCheckoutSignature(razorpayOrderId, paymentId, signature)
    if (!valid) {
      return jsonResponse({ success: false, error: 'Invalid payment signature' }, 400)
    }

    const payment = await fetchPayment(paymentId)
    if (payment.status !== 'captured' && payment.status !== 'authorized') {
      return jsonResponse({ success: false, error: `Payment is ${payment.status}` }, 400)
    }
    if (payment.order_id && payment.order_id !== razorpayOrderId) {
      return jsonResponse({ success: false, error: 'Payment does not match this order' }, 400)
    }

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

    const admin = createClient(supabaseUrl, serviceKey)

    const { data: existing } = await admin
      .from('orders')
      .select('id')
      .eq('payment_id', paymentId)
      .maybeSingle()
    if (existing?.id) {
      return jsonResponse({ success: true, order_id: existing.id, recovered: true })
    }

    const { data: pending } = await admin
      .from('pending_checkouts')
      .select('*')
      .eq('razorpay_order_id', razorpayOrderId)
      .maybeSingle()

    const snapshot: PendingCheckout = pending
      ? {
          user_id: pending.user_id,
          cart_items: pending.cart_items,
          delivery_address: pending.delivery_address,
          instructions: pending.instructions,
          phone: pending.phone,
          email: pending.email,
          apply_coins: pending.apply_coins,
          tip_amount: Number(pending.tip_amount ?? 0),
          delivery_fee: Number(pending.delivery_fee ?? 0),
        }
      : {
          user_id: userData.user.id,
          cart_items: body.cart_items,
          delivery_address: body.delivery_address ?? null,
          instructions: body.instructions ?? null,
          phone: body.customer_phone ?? null,
          email: userData.user.email ?? null,
          apply_coins: Boolean(body.apply_coins),
          tip_amount: Number(body.tip_amount ?? 0),
          delivery_fee: Number(body.delivery_fee ?? 0),
        }

    if (snapshot.user_id !== userData.user.id) {
      return jsonResponse({ success: false, error: 'This payment does not belong to you' }, 403)
    }

    const { data: placed, error: placeError } = await placeFromPending(
      admin,
      snapshot,
      paymentId,
      razorpayOrderId,
      signature,
    )
    if (!placeError && placed?.success === true) {
      return jsonResponse({ success: true, order_id: placed.order_id, recovered: true })
    }

    await admin.rpc('release_checkout_inventory', {
      p_razorpay_order_id: razorpayOrderId,
      p_force: true,
    })

    let refunded = false
    let refundId: string | null = null
    try {
      if (payment.status === 'captured') {
        const refund = await refundPayment(paymentId)
        refunded = true
        refundId = refund?.id ?? null
      }
    } catch (refundErr) {
      console.error('recover-payment refund failed', refundErr)
    }

    const soldOut = placed?.code === 'sold_out' || /sold out|no longer available/i.test(String(placed?.error || ''))
    return jsonResponse({
      success: false,
      refunded,
      refund_id: refundId,
      code: soldOut ? 'sold_out' : placed?.code,
      error: soldOut
        ? 'This meal just sold out. Your payment was refunded and should return in 5–7 business days.'
        : (placed?.error || placeError?.message || 'Could not record the order after payment'),
    }, refunded ? 200 : 500)
  } catch (err) {
    return jsonResponse({ success: false, error: err.message ?? 'Recovery failed' }, 400)
  }
})
