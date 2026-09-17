// Decide when create-split-order should attach Razorpay Route transfers.
// Skip reasons are persisted on meals.transfer_status so release-chef-payout
// can no-op honestly instead of throwing.

import {
  computeMealNetTotal,
  extractAddOnsUnitTotal,
  extractMealId,
  extractQuantity,
  roundCurrency,
  type MealRow,
} from "./pricing.ts"

export const SKIP_NO_ROUTE_ACCOUNT = "skipped_no_route_account"
export const SKIP_MOCK_ACCOUNT = "skipped_mock_account"
export const SKIP_STANDARD_MODE = "skipped_standard_mode"
export const SKIP_TRANSFER_TOO_SMALL = "skipped_transfer_too_small"
export const TRANSFER_ON_HOLD = "on_hold"

export const MIN_TRANSFER_PAISE = 100

export interface ChefAccountRow {
  gateway_account_id?: string | null
}

export interface TransferSpec {
  account: string
  amount: number
  chefId: string
  mealIds: string[]
}

export interface MealPersistUpdate {
  mealIds: string[]
  transferStatus: string
  razorpayTransferId?: string | null
}

export interface RouteTransferPlan {
  transferStatus: string
  skipReason: string | null
  transfers: TransferSpec[]
  mealUpdates: MealPersistUpdate[]
}

export function isMockAccountId(accountId: string | null | undefined): boolean {
  return String(accountId ?? "").startsWith("acc_mock_")
}

export function isRealRouteAccountId(accountId: string | null | undefined): boolean {
  const id = String(accountId ?? "").trim()
  return id.startsWith("acc_") && !isMockAccountId(id)
}

export function extractChefId(
  meal: MealRow & { chef_id?: string | null },
  cartItem?: Record<string, unknown>,
): string {
  const fromMeal = meal.chef_id != null ? String(meal.chef_id).trim() : ""
  if (fromMeal) return fromMeal
  if (!cartItem) return ""
  const raw = cartItem.chef_id ?? cartItem.chefId
  return raw != null ? String(raw).trim() : ""
}

function foodShareForItem(
  item: Record<string, unknown>,
  meal: MealRow,
  now?: Date,
): number {
  const qty = extractQuantity(item)
  const addOns = extractAddOnsUnitTotal(item)
  return roundCurrency(computeMealNetTotal(meal, qty, now) + addOns * qty)
}

export function planRouteTransfers(input: {
  cartItems: Record<string, unknown>[]
  mealsById: Record<string, MealRow & { chef_id?: string | null }>
  chefsById: Record<string, ChefAccountRow>
  chefTransferPaise: number
  now?: Date
}): RouteTransferPlan {
  if (input.chefTransferPaise < MIN_TRANSFER_PAISE) {
    return {
      transferStatus: SKIP_TRANSFER_TOO_SMALL,
      skipReason: SKIP_TRANSFER_TOO_SMALL,
      transfers: [],
      mealUpdates: [{ mealIds: Object.keys(input.mealsById), transferStatus: SKIP_TRANSFER_TOO_SMALL }],
    }
  }

  const byChef = new Map<string, { food: number; mealIds: Set<string>; accountId: string | null }>()

  for (const item of input.cartItems) {
    const mealId = extractMealId(item)
    const meal = input.mealsById[mealId]
    if (!meal) continue
    const chefId = extractChefId(meal, item)
    if (!chefId) continue
    const existing = byChef.get(chefId) ?? {
      food: 0,
      mealIds: new Set<string>(),
      accountId: input.chefsById[chefId]?.gateway_account_id ?? null,
    }
    existing.food = roundCurrency(existing.food + foodShareForItem(item, meal, input.now))
    existing.mealIds.add(mealId)
    byChef.set(chefId, existing)
  }

  if (byChef.size === 0) {
    const mealIds = Object.keys(input.mealsById)
    return {
      transferStatus: SKIP_NO_ROUTE_ACCOUNT,
      skipReason: SKIP_NO_ROUTE_ACCOUNT,
      transfers: [],
      mealUpdates: [{ mealIds, transferStatus: SKIP_NO_ROUTE_ACCOUNT }],
    }
  }

  const totalFood = [...byChef.values()].reduce((sum, row) => sum + row.food, 0)
  const transfers: TransferSpec[] = []
  const mealUpdates: MealPersistUpdate[] = []
  let sawMock = false
  let sawMissing = false

  for (const [chefId, row] of byChef) {
    const mealIds = [...row.mealIds]
    if (!isRealRouteAccountId(row.accountId)) {
      if (isMockAccountId(row.accountId)) {
        sawMock = true
        mealUpdates.push({ mealIds, transferStatus: SKIP_MOCK_ACCOUNT })
      } else {
        sawMissing = true
        mealUpdates.push({ mealIds, transferStatus: SKIP_NO_ROUTE_ACCOUNT })
      }
      continue
    }

    const share = totalFood > 0
      ? Math.round(input.chefTransferPaise * (row.food / totalFood))
      : Math.round(input.chefTransferPaise / byChef.size)
    if (share < MIN_TRANSFER_PAISE) {
      mealUpdates.push({ mealIds, transferStatus: SKIP_TRANSFER_TOO_SMALL })
      continue
    }

    transfers.push({
      account: String(row.accountId),
      amount: share,
      chefId,
      mealIds,
    })
  }

  if (transfers.length === 0) {
    const transferStatus = sawMock && !sawMissing ? SKIP_MOCK_ACCOUNT : SKIP_NO_ROUTE_ACCOUNT
    const hasExplicit = mealUpdates.some((update) => update.transferStatus === transferStatus)
    return {
      transferStatus,
      skipReason: transferStatus,
      transfers: [],
      mealUpdates: hasExplicit ? mealUpdates : [{ mealIds: Object.keys(input.mealsById), transferStatus }],
    }
  }

  for (const transfer of transfers) {
    mealUpdates.push({
      mealIds: transfer.mealIds,
      transferStatus: TRANSFER_ON_HOLD,
    })
  }

  return {
    transferStatus: TRANSFER_ON_HOLD,
    skipReason: null,
    transfers,
    mealUpdates,
  }
}

export function buildRazorpayOrderRequest(input: {
  amountPaise: number
  receipt: string
  transfers: TransferSpec[]
}): Record<string, unknown> {
  const body: Record<string, unknown> = {
    amount: input.amountPaise,
    currency: "INR",
    receipt: input.receipt,
  }
  if (input.transfers.length > 0) {
    body.transfers = input.transfers.map((transfer) => ({
      account: transfer.account,
      amount: transfer.amount,
      currency: "INR",
      on_hold: true,
      notes: { source: "hotpotchef_create_split_order" },
    }))
  }
  return body
}

export function extractTransferIds(rzpOrder: unknown): { id: string; account: string }[] {
  if (!rzpOrder || typeof rzpOrder !== "object") return []
  const transfers = (rzpOrder as { transfers?: unknown }).transfers
  if (!Array.isArray(transfers)) return []
  return transfers
    .filter((row): row is Record<string, unknown> => !!row && typeof row === "object")
    .map((row) => ({
      id: row.id != null ? String(row.id) : "",
      account: row.account != null ? String(row.account) : "",
    }))
}

export function applyTransferIdsToPlan(
  plan: RouteTransferPlan,
  rzpOrder: unknown,
): RouteTransferPlan {
  const ids = extractTransferIds(rzpOrder)
  if (ids.length === 0) return plan

  const mealUpdates = plan.mealUpdates.map((update) => {
    if (update.transferStatus !== TRANSFER_ON_HOLD) return update
    const match = plan.transfers.find((transfer) =>
      transfer.mealIds.some((mealId) => update.mealIds.includes(mealId)),
    )
    const found = match
      ? ids.find((row) => row.account === match.account && row.id)
      : ids.find((row) => row.id)
    return found?.id ? { ...update, razorpayTransferId: found.id } : update
  })

  return { ...plan, mealUpdates }
}
