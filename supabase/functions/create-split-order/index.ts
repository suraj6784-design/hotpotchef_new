import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { jsonResponse, optionsResponse } from '../_shared/cors.ts'
import { createRazorpayOrder } from '../_shared/razorpay.ts'

function asNumber(value: unknown, fallback = 0) {
  const n = Number(value)
  return Number.isFinite(n) ? n : fallback
}

function normalizeCartItems(raw: unknown) {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new Error('Cart is empty')
  }
  return raw.map((item) => {
    const row = (item && typeof item === 'object') ? item as Record<string, unknown> : {}
    const qty = Math.max(1, Math.round(asNumber(row.quantity, 1)))
    const price = asNumber(
      row.discounted_price ?? row.discountedPrice ?? row.price ?? row.base_price ?? row.basePrice,
      0,
    )
    return {
      ...row,
      quantity: qty,
      price,
      chef_id: row.chef_id ?? row.chefId,
      meal_id: row.meal_id ?? row.mealId ?? row.source_meal_id,
      source_meal_id: row.source_meal_id ?? row.meal_id ?? row.mealId,
    }
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return optionsResponse()

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return jsonResponse({ success: false, error: 'Unauthorized' }, 401)

    const body = await req.json()
    const cartItems = normalizeCartItems(body.cart_items)
    const deliveryFee = Math.max(0, Math.min(500, asNumber(body.delivery_fee, 0)))
    const tipAmount = Math.max(0, Math.min(500, asNumber(body.tip_amount, 0)))
    const applyCoins = Boolean(body.apply_coins)

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
    const user = userData.user

    const admin = createClient(supabaseUrl, serviceKey)
    const { data: pricing, error: pricingError } = await admin.rpc('calculate_cart_total', {
      p_items: cartItems,
    })
    if (pricingError) throw new Error(pricingError.message)

    const foodAfterDiscount = asNumber(
      pricing?.grand_total,
      asNumber(pricing?.subtotal, 0) - asNumber(pricing?.discount, 0) + asNumber(pricing?.packaging_fee, 20),
    )
    const packagingAlreadyIncluded = asNumber(pricing?.packaging_fee, 20)
    const foodOnly = Math.max(0, foodAfterDiscount - packagingAlreadyIncluded)
    const billBeforeCoins = foodOnly + packagingAlreadyIncluded + deliveryFee + tipAmount

    let coins = 0
    if (applyCoins) {
      const { data: profile } = await admin.from('users').select('hotpot_coins').eq('id', user.id).maybeSingle()
      coins = Math.min(asNumber(profile?.hotpot_coins, 0), billBeforeCoins)
    }

    const grandTotal = Math.max(0, billBeforeCoins - coins)
    const amountPaise = Math.round(grandTotal * 100)
    if (amountPaise < 100) {
      throw new Error('Payable amount is too small to charge')
    }

    const rzpOrder = await createRazorpayOrder(amountPaise, `hpc_${Date.now()}`, {
      user_id: user.id,
    })

    await admin.rpc('expire_checkout_holds')
    const { data: reserved, error: reserveError } = await admin.rpc('reserve_checkout_inventory', {
      p_razorpay_order_id: rzpOrder.id,
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
      razorpay_order_id: rzpOrder.id,
      cart_items: cartItems,
      delivery_address: body.delivery_address ?? null,
      instructions: body.instructions ?? null,
      phone: body.customer_phone ?? null,
      email: user.email ?? body.customer_email ?? null,
      apply_coins: applyCoins,
      tip_amount: tipAmount,
      delivery_fee: deliveryFee,
      amount_paise: amountPaise,
    })
    if (pendingError) {
      await admin.rpc('release_checkout_inventory', {
        p_razorpay_order_id: rzpOrder.id,
        p_force: true,
      })
      throw new Error(pendingError.message)
    }

    return jsonResponse({
      success: true,
      order_id: rzpOrder.id,
      amount: amountPaise,
      currency: 'INR',
      hold_minutes: 15,
    })
  } catch (err) {
    return jsonResponse({ success: false, error: err.message ?? 'Could not initialize payment' }, 400)
  }
})
