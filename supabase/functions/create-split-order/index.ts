// supabase/functions/create-split-order/index.ts
//
// Contract (keep in sync with lib/services/create_split_order_contract.dart):
// Request: { cart_items, customer_email, delivery_fee, tip_amount, apply_coins }
//   - cart_items may contain multiple meals / chefs (mealId | meal_id | source_meal_id)
//   - client `total_amount` / `meal_id` are NOT used to set the charge
//   - amount is recomputed from meals-table prices + qty + add-ons +
//     packaging + clamped delivery_fee/tip − server coin balance
//   - calculate_cart_total RPC is used for packaging_fee (and food fallback)
// Response: { success, order_id, amount (paise), currency, chef_transfer, breakdown? }
//
// Limitation: payment metadata is still written onto catalog `meals` rows
// (pre-existing schema). For multi-item carts the same Razorpay order_id and
// order-level fee/payout totals are stamped on every meal in the cart.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2"
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

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

function asCartItems(raw: unknown, legacyMealId?: unknown): Record<string, unknown>[] {
  if (Array.isArray(raw) && raw.length > 0) {
    return raw.filter((item): item is Record<string, unknown> => !!item && typeof item === "object")
  }
  // Legacy single-meal clients: treat meal_id as a one-line cart. Price still
  // comes from the meals table, never from client total_amount.
  if (legacyMealId != null && String(legacyMealId).trim() !== "") {
    return [{ mealId: String(legacyMealId).trim(), quantity: 1 }]
  }
  return []
}

async function fetchMealsById(
  supabaseAdmin: SupabaseClient,
  mealIds: string[],
): Promise<Record<string, MealRow>> {
  if (mealIds.length === 0) return {}
  const { data, error } = await supabaseAdmin
    .from("meals")
    .select("id, price, discounted_price, offer_type, discount_value, max_discount_cap, offer_valid_from, offer_valid_until")
    .in("id", mealIds)

  if (error) {
    console.error("Failed to load meals for pricing:", error.message)
    return {}
  }

  const mealsById: Record<string, MealRow> = {}
  for (const row of data ?? []) {
    mealsById[String(row.id)] = row as MealRow
  }
  return mealsById
}

async function fetchRpcCartTotal(
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

async function fetchCoinBalance(
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

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const payload = await req.json()
    const cartItems = asCartItems(payload?.cart_items, payload?.meal_id)
    const customerEmail = payload?.customer_email != null
      ? String(payload.customer_email)
      : null

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    )

    const authHeader = req.headers.get("Authorization") ?? ""
    const jwt = authHeader.replace(/^Bearer\s+/i, "").trim()
    let userId: string | null = null
    if (jwt) {
      const { data } = await supabaseAdmin.auth.getUser(jwt)
      if (data?.user) userId = data.user.id
    }

    const mealIds = collectMealIds(cartItems)

    const [mealsById, rpcTotal, coinBalance] = await Promise.all([
      fetchMealsById(supabaseAdmin, mealIds),
      fetchRpcCartTotal(supabaseAdmin, cartItems),
      payload?.apply_coins
        ? fetchCoinBalance(supabaseAdmin, userId, customerEmail)
        : Promise.resolve(0),
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

    console.log("Authoritative order (server-computed INR):", breakdown)
    console.log("Total amount sent to Razorpay (paise):", totalAmountInPaise)

    const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID")
    const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET")
    if (!razorpayKeyId || !razorpayKeySecret) {
      throw new Error("Payment gateway configuration missing")
    }

    if (totalAmountInPaise < 100) {
      throw new PricingError("Order total is below the ₹1 Razorpay minimum")
    }

    const authHeaderRzp = btoa(`${razorpayKeyId}:${razorpayKeySecret}`)
    const rzpResponse = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Basic ${authHeaderRzp}`,
      },
      body: JSON.stringify({
        amount: totalAmountInPaise,
        currency: "INR",
        receipt: `rcpt_${Date.now()}`,
      }),
    })

    const rzpOrder = await rzpResponse.json()
    if (!rzpResponse.ok || !rzpOrder?.id) {
      throw new Error(rzpOrder.error?.description || "Razorpay order creation failed")
    }
    const razorpayOrderId = String(rzpOrder.id)

    // Least-wrong persistence: stamp every cart meal with the Razorpay order.
    // Catalog meal rows are not a real orders table (see file header).
    const { error: mealUpdateError } = await supabaseAdmin
      .from("meals")
      .update({
        platform_fee: platformFeeInr,
        chef_payout_amount: chefPayoutInr,
        order_id: razorpayOrderId,
        transfer_status: "skipped_standard_mode",
      })
      .in("id", breakdown.mealIds)

    if (mealUpdateError) {
      console.warn("Could not persist payment metadata on meals:", mealUpdateError.message)
    }

    return jsonResponse({
      success: true,
      order_id: razorpayOrderId,
      amount: totalAmountInPaise,
      currency: "INR",
      chef_transfer: chefTransferPaise,
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
})
