import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2"
import {
  basicAuthHeader,
  hasRazorpayKeys,
  RAZORPAY_API_BASE,
  razorpayErrorMessage,
  readRazorpayKeys,
} from "../_shared/razorpay_route.mjs"
import {
  collectMealIds,
  computeAuthoritativeOrder,
  parseMoney,
  PricingError,
  splitPayouts,
  toPaise,
  type MealRow,
  type RpcCartTotal,
} from "./pricing.ts"
import {
  applyTransferIdsToPlan,
  buildRazorpayOrderRequest,
  planRouteTransfers,
  SKIP_STANDARD_MODE,
  type MealPersistUpdate,
} from "./route_transfers.ts"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

export function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

export function asCartItems(raw: unknown, legacyMealId?: unknown): Record<string, unknown>[] {
  if (Array.isArray(raw) && raw.length > 0) {
    return raw.filter((item): item is Record<string, unknown> => !!item && typeof item === "object")
  }
  if (legacyMealId != null && String(legacyMealId).trim() !== "") {
    return [{ mealId: String(legacyMealId).trim(), quantity: 1 }]
  }
  return []
}

export type FetchLike = (input: string | URL | Request, init?: RequestInit) => Promise<Response>

export interface SplitOrderDeps {
  getRazorpayKeys?: () => { keyId: string; keySecret: string }
  fetchImpl?: FetchLike
  now?: () => number
  createSupabase?: () => SupabaseClient
  getUser?: (jwt: string) => Promise<{ id: string } | null>
  fetchMealsById?: (mealIds: string[]) => Promise<Record<string, MealRow & { chef_id?: string | null }>>
  fetchRpcCartTotal?: (cartItems: Record<string, unknown>[]) => Promise<RpcCartTotal | null>
  fetchCoinBalance?: (userId: string | null, customerEmail: string | null) => Promise<number>
  fetchChefsById?: (chefIds: string[]) => Promise<Record<string, { gateway_account_id?: string | null }>>
  persistMealPayments?: (
    mealIds: string[],
    fields: {
      platformFeeInr: number
      chefPayoutInr: number
      orderId: string
      updates: MealPersistUpdate[]
    },
  ) => Promise<void>
}

export async function fetchMealsById(
  supabaseAdmin: SupabaseClient,
  mealIds: string[],
): Promise<Record<string, MealRow & { chef_id?: string | null }>> {
  if (mealIds.length === 0) return {}
  const { data, error } = await supabaseAdmin
    .from("meals")
    .select("id, chef_id, price, discounted_price, offer_type, discount_value, max_discount_cap, offer_valid_from, offer_valid_until")
    .in("id", mealIds)

  if (error) {
    console.error("Failed to load meals for pricing:", error.message)
    return {}
  }

  const mealsById: Record<string, MealRow & { chef_id?: string | null }> = {}
  for (const row of data ?? []) {
    mealsById[String(row.id)] = row as MealRow & { chef_id?: string | null }
  }
  return mealsById
}

export async function fetchRpcCartTotal(
  supabaseAdmin: SupabaseClient,
  cartItems: Record<string, unknown>[],
): Promise<RpcCartTotal | null> {
  try {
    const { data, error } = await supabaseAdmin.rpc("calculate_cart_total", {
      p_items: cartItems,
    })
    if (error || !data || typeof data !== "object") return null
    return data as RpcCartTotal
  } catch (err) {
    console.warn("calculate_cart_total unavailable:", err)
    return null
  }
}

export async function fetchCoinBalance(
  supabaseAdmin: SupabaseClient,
  userId: string | null,
  customerEmail: string | null,
): Promise<number> {
  if (userId) {
    const { data } = await supabaseAdmin
      .from("users")
      .select("hotpot_coins")
      .eq("id", userId)
      .maybeSingle()
    if (data) return parseMoney(data.hotpot_coins)
  }
  if (customerEmail) {
    const { data } = await supabaseAdmin
      .from("users")
      .select("hotpot_coins")
      .eq("email", customerEmail)
      .maybeSingle()
    if (data) return parseMoney(data.hotpot_coins)
  }
  return 0
}

export async function fetchChefsById(
  supabaseAdmin: SupabaseClient,
  chefIds: string[],
): Promise<Record<string, { gateway_account_id?: string | null }>> {
  if (chefIds.length === 0) return {}
  const { data, error } = await supabaseAdmin
    .from("users")
    .select("id, gateway_account_id")
    .in("id", chefIds)
  if (error) {
    console.warn("Failed to load chef Route accounts:", error.message)
    return {}
  }
  const chefs: Record<string, { gateway_account_id?: string | null }> = {}
  for (const row of data ?? []) {
    chefs[String(row.id)] = { gateway_account_id: row.gateway_account_id ?? null }
  }
  return chefs
}

export async function persistMealPayments(
  supabaseAdmin: SupabaseClient,
  mealIds: string[],
  fields: {
    platformFeeInr: number
    chefPayoutInr: number
    orderId: string
    updates: MealPersistUpdate[]
  },
): Promise<void> {
  const base = {
    platform_fee: fields.platformFeeInr,
    chef_payout_amount: fields.chefPayoutInr,
    order_id: fields.orderId,
  }

  if (fields.updates.length === 0) {
    const { error } = await supabaseAdmin
      .from("meals")
      .update({ ...base, transfer_status: SKIP_STANDARD_MODE })
      .in("id", mealIds)
    if (error) console.warn("Could not persist payment metadata on meals:", error.message)
    return
  }

  for (const update of fields.updates) {
    if (update.mealIds.length === 0) continue
    const { error } = await supabaseAdmin
      .from("meals")
      .update({
        ...base,
        transfer_status: update.transferStatus,
        razorpay_transfer_id: update.razorpayTransferId ?? null,
      })
      .in("id", update.mealIds)
    if (error) console.warn("Could not persist payment metadata on meals:", error.message)
  }
}

function collectChefIds(
  mealsById: Record<string, MealRow & { chef_id?: string | null }>,
  cartItems: Record<string, unknown>[],
): string[] {
  const ids = new Set<string>()
  for (const meal of Object.values(mealsById)) {
    if (meal.chef_id) ids.add(String(meal.chef_id))
  }
  for (const item of cartItems) {
    const raw = item.chef_id ?? item.chefId
    if (raw != null && String(raw).trim() !== "") ids.add(String(raw).trim())
  }
  return [...ids]
}

export async function handleCreateSplitOrder(req: Request, deps: SplitOrderDeps = {}): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  const authHeader = req.headers.get("Authorization") ?? ""
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim()
  if (!jwt) {
    return jsonResponse({ error: "Authentication required" }, 401)
  }

  try {
    let supabaseAdmin: SupabaseClient | null = null
    const supabase = () => {
      if (deps.createSupabase) return deps.createSupabase()
      if (!supabaseAdmin) {
        supabaseAdmin = createClient(
          Deno.env.get("SUPABASE_URL") ?? "",
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
        )
      }
      return supabaseAdmin
    }

    let userId: string | null = null
    if (deps.getUser) {
      const user = await deps.getUser(jwt)
      if (user) userId = user.id
    } else {
      const { data } = await supabase().auth.getUser(jwt)
      if (data?.user) userId = data.user.id
    }
    if (!userId) {
      return jsonResponse({ error: "Invalid or expired session" }, 401)
    }

    const payload = await req.json()
    const cartItems = asCartItems(payload?.cart_items, payload?.meal_id)
    const customerEmail = payload?.customer_email != null ? String(payload.customer_email) : null

    const mealIds = collectMealIds(cartItems)
    const fetchMeals = deps.fetchMealsById ?? ((ids: string[]) => fetchMealsById(supabase(), ids))
    const fetchRpc = deps.fetchRpcCartTotal ?? ((items: Record<string, unknown>[]) => fetchRpcCartTotal(supabase(), items))
    const fetchCoins = deps.fetchCoinBalance ?? (
      (uid: string | null, email: string | null) => fetchCoinBalance(supabase(), uid, email)
    )

    const [mealsById, rpcTotal, coinBalance] = await Promise.all([
      fetchMeals(mealIds),
      fetchRpc(cartItems),
      payload?.apply_coins ? fetchCoins(userId, customerEmail) : Promise.resolve(0),
    ])

    const breakdown = computeAuthoritativeOrder({
      cartItems,
      mealsById,
      deliveryFee: parseMoney(payload?.delivery_fee),
      tipAmount: parseMoney(payload?.tip_amount),
      applyCoins: payload?.apply_coins === true,
      coinBalance,
      rpcTotal,
    })

    const totalAmountInPaise = toPaise(breakdown.grandTotal)
    const { platformFeeInr, chefPayoutInr, chefTransferPaise } = splitPayouts(breakdown.grandTotal)

    const keys = (deps.getRazorpayKeys ?? readRazorpayKeys)()
    if (!hasRazorpayKeys(keys)) {
      throw new Error("Payment gateway configuration missing")
    }

    if (totalAmountInPaise < 100) {
      throw new PricingError("Order total is below the ₹1 Razorpay minimum")
    }

    const chefIds = collectChefIds(mealsById, cartItems)
    const fetchChefs = deps.fetchChefsById ?? ((ids: string[]) => fetchChefsById(supabase(), ids))
    const chefsById = await fetchChefs(chefIds)

    let plan = planRouteTransfers({
      cartItems,
      mealsById,
      chefsById,
      chefTransferPaise,
    })

    const receipt = `rcpt_${(deps.now ?? Date.now)()}`
    const orderBody = buildRazorpayOrderRequest({
      amountPaise: totalAmountInPaise,
      receipt,
      transfers: plan.transfers,
    })

    const fetchImpl = deps.fetchImpl ?? globalThis.fetch
    const rzpResponse = await fetchImpl(`${RAZORPAY_API_BASE}/v1/orders`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: basicAuthHeader(keys.keyId, keys.keySecret),
      },
      body: JSON.stringify(orderBody),
    })

    const rzpOrder = await rzpResponse.json()
    if (!rzpResponse.ok || !rzpOrder?.id) {
      throw new Error(razorpayErrorMessage(rzpOrder, "Razorpay order creation failed"))
    }
    const razorpayOrderId = String(rzpOrder.id)
    plan = applyTransferIdsToPlan(plan, rzpOrder)

    const persist = deps.persistMealPayments ?? (
      (ids, fields) => persistMealPayments(supabase(), ids, fields)
    )
    await persist(breakdown.mealIds, {
      platformFeeInr,
      chefPayoutInr,
      orderId: razorpayOrderId,
      updates: plan.mealUpdates,
    })

    return jsonResponse({
      success: true,
      order_id: razorpayOrderId,
      amount: totalAmountInPaise,
      currency: "INR",
      chef_transfer: chefTransferPaise,
      transfer_status: plan.transferStatus,
      transfers: plan.transfers.map((transfer) => ({
        account: transfer.account,
        amount: transfer.amount,
        chef_id: transfer.chefId,
      })),
      breakdown: {
        food_total: breakdown.foodTotal,
        packaging_fee: breakdown.packagingFee,
        delivery_fee: breakdown.deliveryFee,
        tip_amount: breakdown.tipAmount,
        coin_deduction: breakdown.coinDeduction,
        grand_total: breakdown.grandTotal,
      },
    })
  } catch (err) {
    const message = err instanceof PricingError
      ? err.message
      : err instanceof Error
      ? err.message
      : "Payment initialization failed"
    return jsonResponse({ error: message }, 400)
  }
}
