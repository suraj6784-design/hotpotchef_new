import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts"
import {
  computeAuthoritativeOrder,
  computeMealNetTotal,
  DEFAULT_PACKAGING_FEE,
  extractMealId,
  PricingError,
  splitPayouts,
  toPaise,
  type MealRow,
} from "./pricing.ts"

const meal = (overrides: Partial<MealRow> & { id: string; price: number }): MealRow => overrides

Deno.test("prefers mealId over composite cart line id", () => {
  assertEquals(
    extractMealId({ id: "meal-uuid_1710000000", mealId: "meal-uuid" }),
    "meal-uuid",
  )
})

Deno.test("computes multi-item cart from server meal prices, ignoring client total_amount", () => {
  const mealsById = {
    m1: meal({ id: "m1", price: 100 }),
    m2: meal({ id: "m2", price: 80 }),
  }

  const result = computeAuthoritativeOrder({
    cartItems: [
      { mealId: "m1", quantity: 2, total_amount: 1 },
      { meal_id: "m2", quantity: 1 },
    ],
    mealsById,
    deliveryFee: 40,
    tipAmount: 10,
    applyCoins: false,
    coinBalance: 999,
  })

  // 200 + 80 + packaging 20 + delivery 40 + tip 10 = 350
  assertEquals(result.foodTotal, 280)
  assertEquals(result.packagingFee, DEFAULT_PACKAGING_FEE)
  assertEquals(result.deliveryFee, 40)
  assertEquals(result.tipAmount, 10)
  assertEquals(result.coinDeduction, 0)
  assertEquals(result.grandTotal, 350)
  assertEquals(toPaise(result.grandTotal), 35000)
  assertEquals(result.mealIds.sort(), ["m1", "m2"])
})

Deno.test("does not require client total_amount — missing field is the checkout contract", () => {
  const result = computeAuthoritativeOrder({
    cartItems: [{ mealId: "m1", quantity: 1 }],
    mealsById: { m1: meal({ id: "m1", price: 150 }) },
    deliveryFee: 0,
    tipAmount: 0,
    applyCoins: false,
    coinBalance: 0,
  })
  // 150 + 20 packaging
  assertEquals(result.grandTotal, 170)
})

Deno.test("applies server coin balance, not a client-supplied deduction", () => {
  const result = computeAuthoritativeOrder({
    cartItems: [{ mealId: "m1", quantity: 1 }],
    mealsById: { m1: meal({ id: "m1", price: 200 }) },
    deliveryFee: 0,
    tipAmount: 0,
    applyCoins: true,
    coinBalance: 50,
  })
  // 200 + 20 - 50 = 170
  assertEquals(result.coinDeduction, 50)
  assertEquals(result.grandTotal, 170)
})

Deno.test("ignores coins when apply_coins is false even if a balance exists", () => {
  const result = computeAuthoritativeOrder({
    cartItems: [{ mealId: "m1", quantity: 1 }],
    mealsById: { m1: meal({ id: "m1", price: 200 }) },
    deliveryFee: 0,
    tipAmount: 0,
    applyCoins: false,
    coinBalance: 50,
  })
  assertEquals(result.coinDeduction, 0)
  assertEquals(result.grandTotal, 220)
})

Deno.test("clamps abusive delivery fee and tip from the client", () => {
  const result = computeAuthoritativeOrder({
    cartItems: [{ mealId: "m1", quantity: 1 }],
    mealsById: { m1: meal({ id: "m1", price: 100 }) },
    deliveryFee: 99999,
    tipAmount: -20,
    applyCoins: false,
    coinBalance: 0,
  })
  assertEquals(result.deliveryFee, 2000)
  assertEquals(result.tipAmount, 0)
})

Deno.test("applies BOGO against server price", () => {
  const net = computeMealNetTotal(
    meal({ id: "m1", price: 150, offer_type: "BOGO (Buy 1 Get 1)" }),
    3,
  )
  assertEquals(net, 300)
})

Deno.test("applies percentage discount", () => {
  const net = computeMealNetTotal(
    meal({ id: "m1", price: 200, offer_type: "percentage", discount_value: 20 }),
    2,
  )
  assertEquals(net, 320)
})

Deno.test("ignores expired offers", () => {
  const expired = new Date(Date.now() - 60 * 60 * 1000).toISOString()
  const net = computeMealNetTotal(
    meal({
      id: "m1",
      price: 100,
      offer_type: "flat",
      discount_value: 50,
      offer_valid_until: expired,
    }),
    1,
    new Date(),
  )
  assertEquals(net, 100)
})

Deno.test("adds clamped add-on prices per unit", () => {
  const result = computeAuthoritativeOrder({
    cartItems: [{
      mealId: "m1",
      quantity: 2,
      selectedAddOns: [{ id: "a1", title: "Extra", price: 15 }],
    }],
    mealsById: { m1: meal({ id: "m1", price: 100 }) },
    deliveryFee: 0,
    tipAmount: 0,
    applyCoins: false,
    coinBalance: 0,
  })
  // (100 + 15) * 2 + 20 packaging = 250
  assertEquals(result.foodTotal, 230)
  assertEquals(result.grandTotal, 250)
})

Deno.test("falls back to calculate_cart_total when meal rows are missing", () => {
  const result = computeAuthoritativeOrder({
    cartItems: [{ mealId: "ghost", quantity: 1 }],
    mealsById: {},
    deliveryFee: 30,
    tipAmount: 0,
    applyCoins: false,
    coinBalance: 0,
    rpcTotal: { subtotal: 180, packaging_fee: 25 },
  })
  assertEquals(result.foodTotal, 180)
  assertEquals(result.packagingFee, 25)
  assertEquals(result.grandTotal, 235)
})

Deno.test("throws on empty cart — the old missing-total_amount failure mode is gone", () => {
  assertThrows(
    () =>
      computeAuthoritativeOrder({
        cartItems: [],
        mealsById: {},
        deliveryFee: 0,
        tipAmount: 0,
        applyCoins: false,
        coinBalance: 0,
      }),
    PricingError,
    "Cart is empty",
  )
})

Deno.test("split payouts keep 15% platform commission in paise", () => {
  const split = splitPayouts(100)
  assertEquals(split.platformFeeInr, 15)
  assertEquals(split.chefTransferPaise, 8500)
})
