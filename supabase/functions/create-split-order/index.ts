import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { jsonResponse, optionsResponse } from '../_shared/cors.ts'
import { createRazorpayOrder, ensureRazorpayCustomer } from '../_shared/razorpay.ts'
import { quotePaidCheckout } from '../_shared/checkout_quote.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') return optionsResponse()

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return jsonResponse({ success: false, error: 'Unauthorized' }, 401)

    const body = await req.json()
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

    const quoted = await quotePaidCheckout(
      admin,
      user.id,
      body.cart_items,
      body.tip_amount,
      applyCoins,
      body.dropoff_lat,
      body.dropoff_lng,
      Boolean(body.add_membership),
      body.membership_plan_id ?? null,
    )
    const cartItems = quoted.cartItems
    const membershipOnly = cartItems.length === 0 && Boolean(quoted.membershipPlanId)

    const chefIds = [...new Set(
      cartItems
        .map((row) => String(row.chef_id ?? row.chefId ?? '').trim())
        .filter(Boolean),
    )]
    if (!membershipOnly && chefIds.length > 0) {
      const closed: string[] = []
      for (const chefId of chefIds) {
        const { data: open } = await admin.rpc('kitchen_accepting_orders', { p_chef_id: chefId })
        if (open === false) closed.push(chefId)
      }
      if (closed.length > 0) {
        return jsonResponse({
          success: false,
          code: 'kitchen_closed',
          error: 'This kitchen is closed right now',
        }, 400)
      }
    }

    const rzpOrder = await createRazorpayOrder(quoted.amountPaise, `hpc_${Date.now()}`, {
      user_id: user.id,
    })

    const pendingRow = {
      user_id: user.id,
      razorpay_order_id: rzpOrder.id,
      cart_items: cartItems,
      delivery_address: body.delivery_address ?? null,
      instructions: body.instructions ?? null,
      phone: body.customer_phone ?? null,
      email: user.email ?? body.customer_email ?? null,
      apply_coins: quoted.applyCoins,
      tip_amount: quoted.tipAmount,
      delivery_fee: quoted.deliveryFee,
      membership_plan_id: quoted.membershipPlanId,
      membership_fee: quoted.membershipFee,
      amount_paise: quoted.amountPaise,
      dropoff_lat: quoted.dropLat,
      dropoff_lng: quoted.dropLng,
    }
    const { error: pendingError } = await admin
      .from('pending_checkouts')
      .upsert(pendingRow, { onConflict: 'razorpay_order_id' })
    if (pendingError) {
      throw new Error(pendingError.message)
    }

    await admin.rpc('expire_checkout_holds')
    if (!membershipOnly) {
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
    }

    if (quoted.coinsApplied > 0) {
      const { data: coinHold, error: coinError } = await admin.rpc('reserve_checkout_coins', {
        p_razorpay_order_id: rzpOrder.id,
        p_amount: quoted.coinsApplied,
        p_user_id: user.id,
      })
      if (coinError || coinHold?.success !== true) {
        await admin.rpc('release_checkout_inventory', {
          p_razorpay_order_id: rzpOrder.id,
          p_force: true,
        })
        return jsonResponse({
          success: false,
          code: coinHold?.code ?? 'insufficient_coins',
          error: coinHold?.error || coinError?.message || 'HotPot Coins changed. Pay the remainder online.',
        }, 400)
      }
    }

    let razorpayCustomerId: string | null = null
    try {
      const { data: profile } = await admin
        .from('users')
        .select('razorpay_customer_id, name, full_name, phone')
        .eq('id', user.id)
        .maybeSingle()
      razorpayCustomerId = await ensureRazorpayCustomer({
        userId: user.id,
        email: user.email,
        phone: profile?.phone ?? body.customer_phone,
        name: profile?.name ?? profile?.full_name,
        existingId: profile?.razorpay_customer_id,
      })
      if (razorpayCustomerId && razorpayCustomerId !== profile?.razorpay_customer_id) {
        await admin.from('users').update({ razorpay_customer_id: razorpayCustomerId }).eq('id', user.id)
      }
    } catch (_) {
      razorpayCustomerId = null
    }

    return jsonResponse({
      success: true,
      order_id: rzpOrder.id,
      amount: quoted.amountPaise,
      currency: 'INR',
      hold_minutes: 15,
      razorpay_customer_id: razorpayCustomerId,
    })
  } catch (err) {
    return jsonResponse({ success: false, error: err.message ?? 'Could not initialize payment' }, 400)
  }
})
