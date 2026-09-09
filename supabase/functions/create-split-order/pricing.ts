// Pure pricing helpers for create-split-order.
// Authoritative charge is derived from server meal rows + cart qty/add-ons +
// clamped fees/tips + server coin balance. Client `total_amount` is never used.

export const DEFAULT_PACKAGING_FEE = 20
export const DEFAULT_FLASH_SALE_PERCENT = 20
export const MAX_DELIVERY_FEE = 2000
export const MAX_TIP_AMOUNT = 1000
export const MAX_ADDON_UNIT_PRICE = 500
export const MAX_LINE_QUANTITY = 99
export const PLATFORM_COMMISSION_RATE = 0.15

export class PricingError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'PricingError'
  }
}

export type OfferKind = 'none' | 'bogo' | 'percentage' | 'flat' | 'flashSale'

export interface MealRow {
  id: string
  price?: number | string | null
  discounted_price?: number | string | null
  offer_type?: string | null
  discount_value?: number | string | null
  max_discount_cap?: number | string | null
  offer_valid_from?: string | null
  offer_valid_until?: string | null
}

export interface RpcCartTotal {
  subtotal?: number | string | null
  item_total?: number | string | null
  packaging_fee?: number | string | null
}

export interface PricingInput {
  cartItems: Record<string, unknown>[]
  mealsById: Record<string, MealRow>
  deliveryFee: number
  tipAmount: number
  applyCoins: boolean
  coinBalance: number
  packagingFee?: number
  rpcTotal?: RpcCartTotal | null
  now?: Date
}

export interface PricingBreakdown {
  foodTotal: number
  packagingFee: number
  deliveryFee: number
  tipAmount: number
  coinDeduction: number
  grandTotal: number
  mealIds: string[]
}

export function parseMoney(value: unknown): number {
  if (value == null || value === '') return 0
  if (typeof value === 'number') return Number.isFinite(value) ? value : 0
  const parsed = Number(String(value).trim())
  return Number.isFinite(parsed) ? parsed : 0
}

export function roundCurrency(value: number): number {
  if (!Number.isFinite(value)) return 0
  return Math.round(value * 100) / 100
}

export function clampNonNegative(value: number, max: number): number {
  if (!Number.isFinite(value) || value < 0) return 0
  return Math.min(value, max)
}

export function toPaise(amountInr: number): number {
  return Math.round(roundCurrency(amountInr) * 100)
}

export function extractMealId(item: Record<string, unknown>): string {
  const preferred = item.mealId ?? item.meal_id ?? item.source_meal_id
  if (preferred != null && String(preferred).trim() !== '') {
    return String(preferred).trim()
  }
  if (item.id == null) return ''
  return String(item.id).trim()
}

export function extractQuantity(item: Record<string, unknown>): number {
  const qty = Number.parseInt(String(item.quantity ?? 1), 10)
  if (!Number.isFinite(qty) || qty < 1) return 1
  return Math.min(qty, MAX_LINE_QUANTITY)
}

export function extractAddOnsUnitTotal(item: Record<string, unknown>): number {
  const addOns = item.selectedAddOns ?? item.selected_add_ons ?? item.add_ons
  if (!Array.isArray(addOns)) return 0
  return addOns.reduce((sum: number, addon: unknown) => {
    if (!addon || typeof addon !== 'object') return sum
    const price = clampNonNegative(
      parseMoney((addon as { price?: unknown }).price),
      MAX_ADDON_UNIT_PRICE,
    )
    return sum + price
  }, 0)
}

export function normalizeOfferType(raw: unknown): OfferKind {
  if (raw == null) return 'none'
  const normalized = String(raw).toLowerCase().trim()
  if (!normalized || normalized === 'none') return 'none'
  if (normalized.includes('bogo') || normalized.includes('buy 1 get 1')) return 'bogo'
  if (normalized.includes('percent') || normalized.includes('%') || normalized === 'percentage') {
    return 'percentage'
  }
  if (normalized.includes('flat') || normalized.includes('₹') || normalized.includes('flat_discount')) {
    return 'flat'
  }
  if (normalized.includes('flash')) return 'flashSale'
  return 'none'
}

export function isOfferActive(meal: MealRow, now = new Date()): boolean {
  if (normalizeOfferType(meal.offer_type) === 'none') return false

  if (meal.offer_valid_from) {
    const start = new Date(String(meal.offer_valid_from))
    if (!Number.isNaN(start.getTime()) && now < start) return false
  }
  if (meal.offer_valid_until) {
    const end = new Date(String(meal.offer_valid_until))
    if (!Number.isNaN(end.getTime()) && now > end) return false
  }
  return true
}

export function computeMealNetTotal(meal: MealRow, quantity: number, now = new Date()): number {
  const base = Math.max(0, parseMoney(meal.price))
  const discounted = parseMoney(meal.discounted_price)
  if (discounted > 0 && (base <= 0 || discounted < base)) {
    return roundCurrency(discounted * quantity)
  }

  const gross = roundCurrency(base * quantity)
  if (!isOfferActive(meal, now)) return gross

  const offerType = normalizeOfferType(meal.offer_type)
  const discountVal = parseMoney(meal.discount_value)
  const maxCap = parseMoney(meal.max_discount_cap)
  const hasCap = maxCap > 0

  let net = gross
  switch (offerType) {
    case 'bogo': {
      const payableQty = Math.floor(quantity / 2) + (quantity % 2)
      net = roundCurrency(base * payableQty)
      break
    }
    case 'percentage': {
      const percent = Math.min(100, Math.max(0, discountVal))
      let totalDiscount = roundCurrency(base * (percent / 100) * quantity)
      if (hasCap) totalDiscount = Math.min(totalDiscount, maxCap)
      net = roundCurrency(Math.max(0, gross - totalDiscount))
      break
    }
    case 'flat': {
      const unitDiscount = Math.min(base, Math.max(0, discountVal))
      let totalDiscount = roundCurrency(unitDiscount * quantity)
      if (hasCap) totalDiscount = Math.min(totalDiscount, maxCap)
      net = roundCurrency(Math.max(0, gross - totalDiscount))
      break
    }
    case 'flashSale': {
      const effective = discountVal > 0 ? discountVal : DEFAULT_FLASH_SALE_PERCENT
      const percent = Math.min(100, Math.max(0, effective))
      let totalDiscount = roundCurrency(base * (percent / 100) * quantity)
      if (hasCap) totalDiscount = Math.min(totalDiscount, maxCap)
      net = roundCurrency(Math.max(0, gross - totalDiscount))
      break
    }
    default:
      net = gross
  }
  return net
}

export function collectMealIds(cartItems: Record<string, unknown>[]): string[] {
  const ids = cartItems
    .map(extractMealId)
    .filter((id) => id.length > 0)
  return [...new Set(ids)]
}

export function computeAuthoritativeOrder(input: PricingInput): PricingBreakdown {
  if (!Array.isArray(input.cartItems) || input.cartItems.length === 0) {
    throw new PricingError('Cart is empty')
  }

  const mealIds = collectMealIds(input.cartItems)
  if (mealIds.length === 0) {
    throw new PricingError('Cart items are missing meal ids')
  }

  const missing = mealIds.filter((id) => !input.mealsById[id])
  let foodTotal = 0

  if (missing.length === 0) {
    for (const item of input.cartItems) {
      const mealId = extractMealId(item)
      const meal = input.mealsById[mealId]
      const qty = extractQuantity(item)
      const addOns = extractAddOnsUnitTotal(item)
      foodTotal += computeMealNetTotal(meal, qty, input.now) + roundCurrency(addOns * qty)
    }
    foodTotal = roundCurrency(foodTotal)
  }

  const rpcFood = roundCurrency(
    parseMoney(input.rpcTotal?.subtotal ?? input.rpcTotal?.item_total),
  )
  if (foodTotal <= 0 && rpcFood > 0) {
    foodTotal = rpcFood
  }

  if (foodTotal <= 0) {
    if (missing.length > 0) {
      throw new PricingError('One or more cart meals are no longer available')
    }
    throw new PricingError('Unable to compute a valid food total from cart meals')
  }

  const rpcPackaging = parseMoney(input.rpcTotal?.packaging_fee)
  const packagingFee = roundCurrency(
    rpcPackaging > 0
      ? rpcPackaging
      : (input.packagingFee != null && input.packagingFee > 0
        ? input.packagingFee
        : DEFAULT_PACKAGING_FEE),
  )

  const deliveryFee = roundCurrency(clampNonNegative(input.deliveryFee, MAX_DELIVERY_FEE))
  const tipAmount = roundCurrency(clampNonNegative(input.tipAmount, MAX_TIP_AMOUNT))
  const subtotal = roundCurrency(foodTotal + packagingFee + deliveryFee + tipAmount)

  const coinBalance = input.applyCoins
    ? clampNonNegative(input.coinBalance, subtotal)
    : 0
  const coinDeduction = roundCurrency(Math.min(coinBalance, subtotal))
  const grandTotal = roundCurrency(Math.max(0, subtotal - coinDeduction))

  return {
    foodTotal,
    packagingFee,
    deliveryFee,
    tipAmount,
    coinDeduction,
    grandTotal,
    mealIds,
  }
}

export function splitPayouts(grandTotalInr: number): { platformFeeInr: number; chefPayoutInr: number; chefTransferPaise: number } {
  const totalPaise = toPaise(grandTotalInr)
  const platformCommissionPaise = Math.round(grandTotalInr * PLATFORM_COMMISSION_RATE * 100)
  const chefTransferPaise = totalPaise - platformCommissionPaise
  return {
    platformFeeInr: platformCommissionPaise / 100,
    chefPayoutInr: chefTransferPaise / 100,
    chefTransferPaise,
  }
}
