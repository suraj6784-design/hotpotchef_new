import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { jsonResponse, optionsResponse } from '../_shared/cors.ts'
import { adminClient, requireUser } from '../_shared/guard.ts'

function asNumber(value: unknown, fallback = 0) {
  const n = Number(value)
  return Number.isFinite(n) ? n : fallback
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return optionsResponse()

  try {
    const auth = await requireUser(req)
    if (auth instanceof Response) return auth
    const { user, userClient } = auth

    const body = await req.json()
    const cartItems = body.cart_items
    if (!Array.isArray(cartItems) || cartItems.length === 0) {
      return jsonResponse({ success: false, error: 'Cart is empty' }, 400)
    }

    const dropLat = body.dropoff_lat == null ? null : asNumber(body.dropoff_lat, NaN)
    const dropLng = body.dropoff_lng == null ? null : asNumber(body.dropoff_lng, NaN)
    const tipAmount = Math.max(0, Math.min(500, asNumber(body.tip_amount, 0)))

    const admin = adminClient()
    const { error: rateError } = await userClient.rpc('assert_user_rate_limit', {
      p_scope: 'checkout',
      p_limit: 8,
      p_window_minutes: 15,
    })
    if (rateError) {
      return jsonResponse({
        success: false,
        code: 'rate_limited',
        error: rateError.message || 'Too many checkout attempts. Wait a few minutes.',
      }, 429)
    }

    const { data: feeRow, error: feeError } = await admin.rpc('quote_checkout_delivery_fee', {
      p_items: cartItems,
      p_drop_lat: Number.isFinite(dropLat) ? dropLat : null,
      p_drop_lng: Number.isFinite(dropLng) ? dropLng : null,
    })
    if (feeError) {
      return jsonResponse({ success: false, error: feeError.message || 'Could not quote delivery' }, 400)
    }
    const deliveryFee = asNumber(feeRow, 0)

    const { data: pricing, error: quoteError } = await admin.rpc('calculate_cart_total', {
      p_items: cartItems,
      p_user_id: user.id,
    })
    if (quoteError) {
      return jsonResponse({
        success: false,
        error: quoteError.message || 'Could not price this cart from the live menu',
      }, 400)
    }
    const foodOnly = asNumber(pricing?.items_total ?? pricing?.item_total, 0)
    const packaging = asNumber(pricing?.packaging_fee, 20)
    const billBeforeCoins = foodOnly + packaging + deliveryFee + tipAmount
    if (foodOnly <= 0) {
      return jsonResponse({ success: false, error: 'Cart prices could not be verified' }, 400)
    }

    const { data: profile } = await admin.from('users').select('hotpot_coins').eq('id', user.id).maybeSingle()
    const coins = asNumber(profile?.hotpot_coins, 0)
    if (coins + 0.001 < billBeforeCoins) {
      return jsonResponse({
        success: false,
        error: 'HotPot Coins do not cover this order. Pay the remainder online.',
      }, 400)
    }

    const paymentId = `coins_${user.id}_${Date.now()}`
    await admin.rpc('expire_checkout_holds')
    const { data: reserved, error: reserveError } = await admin.rpc('reserve_checkout_inventory', {
      p_razorpay_order_id: paymentId,
      p_cart_items: cartItems,
      p_user_id: user.id,
    })
    if (reserveError || reserved?.success !== true) {
      return jsonResponse({
        success: false,
        code: reserved?.code ?? 'sold_out',
        error: reserved?.error || reserveError?.message || 'This meal just sold out. Nothing was charged.',
      })
    }

    const { error: pendingError } = await admin.from('pending_checkouts').insert({
      user_id: user.id,
      razorpay_order_id: paymentId,
      cart_items: cartItems,
      delivery_address: body.delivery_address ?? null,
      instructions: body.instructions ?? null,
      phone: body.customer_phone ?? null,
      email: user.email ?? body.customer_email ?? null,
      apply_coins: true,
      tip_amount: tipAmount,
      delivery_fee: deliveryFee,
      amount_paise: 0,
      dropoff_lat: Number.isFinite(dropLat) ? dropLat : null,
      dropoff_lng: Number.isFinite(dropLng) ? dropLng : null,
    })
    if (pendingError) {
      await admin.rpc('release_checkout_inventory', {
        p_razorpay_order_id: paymentId,
        p_force: true,
      })
      throw new Error(pendingError.message)
    }

    const { data: placed, error: placeError } = await admin.rpc('place_customer_order', {
      p_customer_email: user.email ?? body.customer_email ?? null,
      p_customer_phone: body.customer_phone ?? null,
      p_delivery_address: body.delivery_address ?? null,
      p_instructions: body.instructions ?? null,
      p_cart_items: cartItems,
      p_apply_coins: true,
      p_idempotency_key: paymentId,
      p_user_id: user.id,
      p_tip_amount: tipAmount,
      p_delivery_fee: deliveryFee,
      p_payment_id: paymentId,
      p_razorpay_order_id: paymentId,
      p_razorpay_signature: null,
    })
    if (placeError || placed?.success !== true) {
      await admin.rpc('release_checkout_inventory', {
        p_razorpay_order_id: paymentId,
        p_force: true,
      })
      return jsonResponse({
        success: false,
        code: placed?.code,
        error: placed?.error || placeError?.message || 'Could not record the coin-paid order.',
      }, 400)
    }

    return jsonResponse({ success: true, order_id: placed.order_id })
  } catch (err) {
    return jsonResponse({ success: false, error: err.message ?? 'Could not place coin order' }, 400)
  }
})
