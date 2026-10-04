export const DEFAULT_PLATFORM_MARGIN_RATE = 0.15

/// Food total at which the diner delivery fee stays ₹0.
export const FREE_DELIVERY_MIN_FOOD = 199

/// Driver payout on that free delivery. ₹20 is the product amount already
/// used at this threshold (packaging on ₹199+ orders). Deducted from the chef.
export const FREE_DELIVERY_DRIVER_PAYOUT = 20

function asNumber(value: unknown, fallback = 0) {
  const n = Number(value)
  return Number.isFinite(n) ? n : fallback
}

export function roundMoney(value: number) {
  return Math.round(value * 100) / 100
}

export function parseOrderItems(raw: unknown): Record<string, unknown>[] {
  if (Array.isArray(raw)) {
    return raw.filter((item) => item && typeof item === 'object') as Record<string, unknown>[]
  }
  if (typeof raw === 'string' && raw.trim()) {
    try {
      const parsed = JSON.parse(raw)
      if (Array.isArray(parsed)) {
        return parsed.filter((item) => item && typeof item === 'object')
      }
    } catch {
      return []
    }
  }
  return []
}

export function lineItemUnitPrice(item: Record<string, unknown>) {
  const unit = asNumber(item.price ?? item.unit_price ?? item.base_price ?? item.basePrice, 0)
  const discounted = asNumber(item.discounted_price ?? item.discountedPrice, 0)
  if (discounted > 0 && (unit <= 0 || discounted <= unit + 0.001)) return discounted
  return unit
}

export function itemsTotalFromLines(items: Record<string, unknown>[]) {
  return items.reduce((sum, item) => {
    const qty = Math.max(1, Math.round(asNumber(item.quantity, 1)))
    return sum + lineItemUnitPrice(item) * qty
  }, 0)
}

/// Charged food on the order. Prefers `line_net` so free-delivery chef math
/// matches the driver card and `complete_delivery_order`.
export function chargedFoodTotal(items: Record<string, unknown>[]): number {
  return roundMoney(items.reduce((sum, item) => {
    const lineNet = asNumber(item.line_net, 0)
    if (lineNet > 0) return sum + lineNet
    const qty = Math.max(1, Math.round(asNumber(item.quantity, 1)))
    return sum + lineItemUnitPrice(item) * qty
  }, 0))
}

export function chefPayoutBreakdown(
  itemsTotal: number,
  packagingFee: number,
  marginRate = DEFAULT_PLATFORM_MARGIN_RATE,
) {
  const base = roundMoney(Math.max(0, itemsTotal + packagingFee))
  const chefPayout = roundMoney(base * (1 - marginRate))
  return {
    foodAndPackaging: base,
    marginRate,
    margin: roundMoney(base - chefPayout),
    chefPayout,
  }
}

/// Mirrors ServiceType.usesDeliveryPartner for display strings such as
/// "Delivery Partner" and "Chef-Self".
export function serviceUsesDeliveryPartner(value: string): boolean {
  const token = value.toLowerCase().split(',')[0].trim()
  if (!token) return true
  if (token.includes('self') || token === 'delivery_self') return false
  if (token.includes('pickup') || token.includes('pick up')) return false
  if (token.includes('dine')) return false
  return true
}

export function orderUsesDeliveryPartner(
  orderType: string,
  items: Record<string, unknown>[] = [],
): boolean {
  const raw = orderType.trim()
  if (raw) return serviceUsesDeliveryPartner(raw)
  for (const item of items) {
    const token = String(
      item.selected_service_type ?? item.service_type ?? item.serviceType ?? '',
    ).trim()
    if (!token) continue
    if (!serviceUsesDeliveryPartner(token)) return false
  }
  return true
}

/// ₹0 unless this is a partner run whose diner delivery fee is ₹0 because
/// food is at least ₹199.
export function freeDeliveryDriverStipend(input: {
  foodTotal: number
  deliveryFee: number
  partnerDelivery: boolean
}): number {
  if (!input.partnerDelivery) return 0
  if (input.deliveryFee > 0) return 0
  if (input.foodTotal + 0.001 < FREE_DELIVERY_MIN_FOOD) return 0
  return FREE_DELIVERY_DRIVER_PAYOUT
}

export function chefTakeHomeAfterDriverStipend(grossChef: number, stipend: number): number {
  return roundMoney(Math.max(0, grossChef - Math.max(0, stipend)))
}
