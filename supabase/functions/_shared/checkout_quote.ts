import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

export function asNumber(value: unknown, fallback = 0) {
  const n = Number(value)
  return Number.isFinite(n) ? n : fallback
}

export function packagingFeeForLoyaltyTier(_tier: unknown) {
  return 20
}

export function packagingFeeFromFoodTotal(food: number) {
  if (!Number.isFinite(food) || food <= 0) return 0
  return food >= 199 ? 20 : 10
}

export function normalizeCartItems(raw: unknown, allowEmpty = false) {
  if (!Array.isArray(raw) || raw.length === 0) {
    if (allowEmpty) return []
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

export type QuotedCheckout = {
  cartItems: ReturnType<typeof normalizeCartItems>
  tipAmount: number
  applyCoins: boolean
  coinsApplied: number
  deliveryFee: number
  membershipFee: number
  membershipPlanId: string | null
  amountPaise: number
  dropLat: number | null
  dropLng: number | null
}

export async function quotePaidCheckout(
  admin: SupabaseClient,
  userId: string,
  rawCart: unknown,
  tipRaw: unknown,
  applyCoins: boolean,
  dropLatRaw: unknown,
  dropLngRaw: unknown,
  addMembership = false,
  planIdRaw: unknown = null,
): Promise<QuotedCheckout> {
  const membershipOnly = addMembership && (!Array.isArray(rawCart) || rawCart.length === 0)
  const cartItems = normalizeCartItems(rawCart, membershipOnly)
  const tipAmount = Math.max(0, Math.min(500, asNumber(tipRaw, 0)))
  const dropLat = dropLatRaw == null ? null : asNumber(dropLatRaw, NaN)
  const dropLng = dropLngRaw == null ? null : asNumber(dropLngRaw, NaN)

  let membershipFee = 0
  let membershipPlanId: string | null = null
  if (addMembership) {
    const planId = typeof planIdRaw === 'string' && planIdRaw.trim() ? planIdRaw.trim() : null
    const { data: quote, error: memError } = await admin.rpc('membership_checkout_quote', {
      p_user_id: userId,
      p_plan_id: planId,
    })
    if (memError) {
      throw new Error(memError.message || 'Could not quote membership')
    }
    if (quote?.eligible === true && quote?.plan_id) {
      membershipFee = Math.max(0, asNumber(quote.offer_price_inr, 0))
      membershipPlanId = String(quote.plan_id)
    }
  }

  if (membershipOnly) {
    if (!membershipPlanId || membershipFee < 1) {
      throw new Error('Family member is not available on this account')
    }
    const amountPaise = Math.round(membershipFee * 100)
    if (amountPaise < 100) {
      throw new Error('Payable amount is too small to charge')
    }
    return {
      cartItems,
      tipAmount: 0,
      applyCoins: false,
      coinsApplied: 0,
      deliveryFee: 0,
      membershipFee,
      membershipPlanId,
      amountPaise,
      dropLat: null,
      dropLng: null,
    }
  }

  const { data: quotedFee, error: feeError } = await admin.rpc('quote_customer_delivery_fee', {
    p_items: cartItems,
    p_drop_lat: Number.isFinite(dropLat) ? dropLat : null,
    p_drop_lng: Number.isFinite(dropLng) ? dropLng : null,
    p_user_id: userId,
  })
  if (feeError) {
    throw new Error(feeError.message || 'Could not quote delivery')
  }
  let deliveryFee = asNumber(quotedFee, 0)
  if (membershipPlanId) deliveryFee = 0

  let packagingAlreadyIncluded = 20
  const { data: pricing, error: quoteError } = await admin.rpc('calculate_cart_total', {
    p_items: cartItems,
    p_user_id: userId,
  })
  if (quoteError) {
    throw new Error(quoteError.message || 'Could not price this cart from the live menu')
  }
  const foodOnly = asNumber(pricing?.items_total ?? pricing?.item_total, 0)
  if (foodOnly <= 0) {
    throw new Error('Cart prices could not be verified')
  }
  if (pricing?.packaging_fee != null) {
    packagingAlreadyIncluded = asNumber(pricing.packaging_fee, packagingAlreadyIncluded)
  } else {
    packagingAlreadyIncluded = packagingFeeFromFoodTotal(foodOnly)
  }
  const mealBill = foodOnly + packagingAlreadyIncluded + deliveryFee + tipAmount

  const coinsAllowed = cartItems.every((row) => {
    const flag = row.accepts_hotpot_coins
    return !(flag === false || flag === 'false')
  })

  let coins = 0
  if (applyCoins && coinsAllowed) {
    const { data: profile } = await admin.from('users').select('hotpot_coins').eq('id', userId).maybeSingle()
    coins = Math.min(asNumber(profile?.hotpot_coins, 0), mealBill)
  }

  const grandTotal = Math.max(0, mealBill - coins) + membershipFee
  const amountPaise = Math.round(grandTotal * 100)
  if (amountPaise < 100) {
    throw new Error('Payable amount is too small to charge')
  }

  return {
    cartItems,
    tipAmount,
    applyCoins: applyCoins && coinsAllowed,
    coinsApplied: coins,
    deliveryFee,
    membershipFee,
    membershipPlanId,
    amountPaise,
    dropLat: Number.isFinite(dropLat) ? dropLat : null,
    dropLng: Number.isFinite(dropLng) ? dropLng : null,
  }
}

export function pendingCartIsEmpty(cart: unknown) {
  return !Array.isArray(cart) || cart.length === 0
}

export async function grantMembershipFromPending(
  admin: SupabaseClient,
  pending: Record<string, unknown>,
) {
  const planId = String(pending.membership_plan_id ?? '').trim()
  const userId = String(pending.user_id ?? '').trim()
  const amount = asNumber(pending.membership_fee, 0)
  if (!planId || !userId) {
    return { data: { success: false, error: 'Missing Family member checkout' }, error: null }
  }
  return await admin.rpc('grant_paid_membership', {
    p_user_id: userId,
    p_plan_id: planId,
    p_amount: amount,
  })
}
