export const DEFAULT_PLATFORM_MARGIN_RATE = 0.15

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
