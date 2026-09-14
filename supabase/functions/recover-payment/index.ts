import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { jsonResponse, optionsResponse } from '../_shared/cors.ts'
import { fetchPayment, refundPayment, verifyCheckoutSignature } from '../_shared/razorpay.ts'
import { quotePaidCheckout } from '../_shared/checkout_quote.ts'

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

async function refundCaptured(
  payment: { status?: string },
  paymentId: string,
) {
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
  return { refunded, refundId }
}

function failPlace(
  placed: { code?: string; error?: string } | null,
  placeError: { message?: string } | null,
  refunded: boolean,
  refundId: string | null,
) {
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
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return optionsResponse()

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return jsonResponse({ success: false, error: 'Unauthorized' }, 401)

    const body = await req.json()
    const paymentId = String(body.payment_id ?? '')
    let razorpayOrderId = String(body.razorpay_order_id ?? body.order_id ?? '').trim()
    const signature = String(body.razorpay_signature ?? body.signature ?? '')

    if (!paymentId || !signature) {
      return jsonResponse({ success: false, error: 'Missing payment verification fields' }, 400)
    }

    const payment = await fetchPayment(paymentId)
    if (payment.status !== 'captured' && payment.status !== 'authorized') {
      return jsonResponse({ success: false, error: `Payment is ${payment.status}` }, 400)
    }

    const paymentOrderId = String(payment.order_id ?? '').trim()
    if (!razorpayOrderId && paymentOrderId) {
      razorpayOrderId = paymentOrderId
    }
    if (!razorpayOrderId) {
      return jsonResponse({ success: false, error: 'Missing payment order' }, 400)
    }
    if (paymentOrderId && paymentOrderId !== razorpayOrderId) {
      razorpayOrderId = paymentOrderId
    }

    const valid = await verifyCheckoutSignature(razorpayOrderId, paymentId, signature)
    if (!valid) {
      return jsonResponse({ success: false, error: 'Invalid payment signature' }, 400)
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

    const { error: rateError } = await userClient.rpc('assert_user_rate_limit', {
      p_scope: 'recover_payment',
      p_limit: 8,
      p_window_minutes: 15,
    })
    if (rateError) {
      return jsonResponse({
        success: false,
        code: 'rate_limited',
        error: rateError.message || 'Too many recovery attempts. Wait a few minutes.',
      }, 429)
    }

    const admin = createClient(supabaseUrl, serviceKey)

    const { data: existingByPay } = await admin
      .from('orders')
      .select('id')
      .eq('payment_id', paymentId)
      .maybeSingle()
    if (existingByPay?.id) {
      return jsonResponse({ success: true, order_id: existingByPay.id, recovered: true })
    }

    const { data: existingByOrder } = await admin
      .from('orders')
      .select('id')
      .eq('razorpay_order_id', razorpayOrderId)
      .maybeSingle()
    if (existingByOrder?.id) {
      return jsonResponse({ success: true, order_id: existingByOrder.id, recovered: true })
    }

    let { data: pending } = await admin
      .from('pending_checkouts')
      .select('*')
      .eq('razorpay_order_id', razorpayOrderId)
      .maybeSingle()

    if (!pending && Array.isArray(body.cart_items) && body.cart_items.length > 0) {
      try {
        const quoted = await quotePaidCheckout(
          admin,
          userData.user.id,
          body.cart_items,
          body.tip_amount,
          Boolean(body.apply_coins),
          body.dropoff_lat,
          body.dropoff_lng,
        )
        if (Number(payment.amount) !== quoted.amountPaise) {
          await admin.rpc('release_checkout_inventory', {
            p_razorpay_order_id: razorpayOrderId,
            p_force: true,
          })
          const refund = await refundCaptured(payment, paymentId)
          return jsonResponse({
            success: false,
            refunded: refund.refunded,
            refund_id: refund.refundId,
            error: 'Payment amount does not match this checkout',
          }, refund.refunded ? 200 : 400)
        }
        const rebuilt = {
          user_id: userData.user.id,
          razorpay_order_id: razorpayOrderId,
          cart_items: quoted.cartItems,
          delivery_address: body.delivery_address ?? null,
          instructions: body.instructions ?? null,
          phone: body.customer_phone ?? null,
          email: userData.user.email ?? body.customer_email ?? null,
          apply_coins: quoted.applyCoins,
          tip_amount: quoted.tipAmount,
          delivery_fee: quoted.deliveryFee,
          amount_paise: quoted.amountPaise,
          dropoff_lat: quoted.dropLat,
          dropoff_lng: quoted.dropLng,
        }
        const { data: upserted, error: upsertError } = await admin
          .from('pending_checkouts')
          .upsert(rebuilt, { onConflict: 'razorpay_order_id' })
          .select('*')
          .maybeSingle()
        if (upsertError) {
          pending = rebuilt
        } else {
          pending = upserted ?? rebuilt
        }
      } catch (quoteErr) {
        console.error('recover-payment rebuild quote failed', quoteErr)
      }
    }

    if (!pending) {
      await admin.rpc('release_checkout_inventory', {
        p_razorpay_order_id: razorpayOrderId,
        p_force: true,
      })
      const refund = await refundCaptured(payment, paymentId)
      return jsonResponse({
        success: false,
        refunded: refund.refunded,
        refund_id: refund.refundId,
        error: refund.refunded
          ? 'We could not record this order, so the payment was refunded. It should return in 5–7 business days.'
          : 'No verified checkout for this payment',
      }, refund.refunded ? 200 : 400)
    }

    const expectedPaise = Number(pending.amount_paise ?? 0)
    if (expectedPaise > 0 && Number(payment.amount) !== expectedPaise) {
      await admin.rpc('release_checkout_inventory', {
        p_razorpay_order_id: razorpayOrderId,
        p_force: true,
      })
      const refund = await refundCaptured(payment, paymentId)
      return jsonResponse({
        success: false,
        refunded: refund.refunded,
        refund_id: refund.refundId,
        error: 'Payment amount does not match this checkout',
      }, refund.refunded ? 200 : 400)
    }

    const snapshot: PendingCheckout = {
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

    const refund = await refundCaptured(payment, paymentId)
    return failPlace(placed, placeError, refund.refunded, refund.refundId)
  } catch (err) {
    return jsonResponse({ success: false, error: err.message ?? 'Recovery failed' }, 400)
  }
})
