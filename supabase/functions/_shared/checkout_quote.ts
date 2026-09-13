import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

export function asNumber(value: unknown, fallback = 0) {
  const n = Number(value)
  return Number.isFinite(n) ? n : fallback
}

export function packagingFeeForLoyaltyTier(tier: unknown) {
  const name = String(tier ?? '').toLowerCase()
  if (name.includes('gold')) return 0
  return 20
}

export function normalizeCartItems(raw: unknown) {
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

export type QuotedCheckout = {
  cartItems: ReturnType<typeof normalizeCartItems>
  tipAmount: number
  applyCoins: boolean
  deliveryFee: number
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
): Promise<QuotedCheckout> {
  const cartItems = normalizeCartItems(rawCart)
  const tipAmount = Math.max(0, Math.min(500, asNumber(tipRaw, 0)))
  const dropLat = dropLatRaw == null ? null : asNumber(dropLatRaw, NaN)
  const dropLng = dropLngRaw == null ? null : asNumber(dropLngRaw, NaN)

  const { data: quotedFee, error: feeError } = await admin.rpc('quote_checkout_delivery_fee', {
    p_items: cartItems,
    p_drop_lat: Number.isFinite(dropLat) ? dropLat : null,
    p_drop_lng: Number.isFinite(dropLng) ? dropLng : null,
  })
  if (feeError) {
    throw new Error(feeError.message || 'Could not quote delivery')
  }
  const deliveryFee = asNumber(quotedFee, 0)

  const { data: gam } = await admin
    .from('user_gamification')
    .select('loyalty_tier')
    .eq('user_id', userId)
    .maybeSingle()
  let packagingAlreadyIncluded = packagingFeeForLoyaltyTier(gam?.loyalty_tier)
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
  }
  const billBeforeCoins = foodOnly + packagingAlreadyIncluded + deliveryFee + tipAmount

  const coinsAllowed = cartItems.every((row) => {
    const flag = row.accepts_hotpot_coins
    return !(flag === false || flag === 'false')
  })

  let coins = 0
  if (applyCoins && coinsAllowed) {
    const { data: profile } = await admin.from('users').select('hotpot_coins').eq('id', userId).maybeSingle()
    coins = Math.min(asNumber(profile?.hotpot_coins, 0), billBeforeCoins)
  }

  const grandTotal = Math.max(0, billBeforeCoins - coins)
  const amountPaise = Math.round(grandTotal * 100)
  if (amountPaise < 100) {
    throw new Error('Payable amount is too small to charge')
  }

  return {
    cartItems,
    tipAmount,
    applyCoins: applyCoins && coinsAllowed,
    deliveryFee,
    amountPaise,
    dropLat: Number.isFinite(dropLat) ? dropLat : null,
    dropLng: Number.isFinite(dropLng) ? dropLng : null,
  }
}
