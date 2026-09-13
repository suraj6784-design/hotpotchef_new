import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts"
import {
  applyTransferIdsToPlan,
  buildRazorpayOrderRequest,
  isRealRouteAccountId,
  planRouteTransfers,
  SKIP_MOCK_ACCOUNT,
  SKIP_NO_ROUTE_ACCOUNT,
  SKIP_TRANSFER_TOO_SMALL,
  TRANSFER_ON_HOLD,
} from "./route_transfers.ts"

const meal = { id: "m1", chef_id: "chef-1", price: 200 }

Deno.test("mock gateway ids are not treated as Route linked accounts", () => {
  assertEquals(isRealRouteAccountId("acc_mock_1"), false)
  assertEquals(isRealRouteAccountId("acc_RZPtest123"), true)
  assertEquals(isRealRouteAccountId(""), false)
})

Deno.test("skips standard Route transfer when the chef has no linked account", () => {
  const plan = planRouteTransfers({
    cartItems: [{ mealId: "m1", quantity: 1 }],
    mealsById: { m1: meal },
    chefsById: { "chef-1": { gateway_account_id: null } },
    chefTransferPaise: 17000,
  })
  assertEquals(plan.transferStatus, SKIP_NO_ROUTE_ACCOUNT)
  assertEquals(plan.transfers.length, 0)
})

Deno.test("skips when the chef only has an acc_mock_* account", () => {
  const plan = planRouteTransfers({
    cartItems: [{ mealId: "m1", quantity: 1 }],
    mealsById: { m1: meal },
    chefsById: { "chef-1": { gateway_account_id: "acc_mock_1700" } },
    chefTransferPaise: 17000,
  })
  assertEquals(plan.transferStatus, SKIP_MOCK_ACCOUNT)
  assertEquals(plan.transfers.length, 0)
})

Deno.test("attaches an on-hold Route transfer for a real linked account", () => {
  const plan = planRouteTransfers({
    cartItems: [{ mealId: "m1", quantity: 1 }],
    mealsById: { m1: meal },
    chefsById: { "chef-1": { gateway_account_id: "acc_RZPtest123" } },
    chefTransferPaise: 17000,
  })
  assertEquals(plan.transferStatus, TRANSFER_ON_HOLD)
  assertEquals(plan.transfers, [{
    account: "acc_RZPtest123",
    amount: 17000,
    chefId: "chef-1",
    mealIds: ["m1"],
  }])

  const order = buildRazorpayOrderRequest({
    amountPaise: 20000,
    receipt: "rcpt_1",
    transfers: plan.transfers,
  })
  assertEquals(order.amount, 20000)
  assertEquals((order.transfers as { account: string; on_hold: boolean }[])[0].account, "acc_RZPtest123")
  assertEquals((order.transfers as { on_hold: boolean }[])[0].on_hold, true)
})

Deno.test("skips transfers below the Razorpay ₹1 minimum", () => {
  const plan = planRouteTransfers({
    cartItems: [{ mealId: "m1", quantity: 1 }],
    mealsById: { m1: meal },
    chefsById: { "chef-1": { gateway_account_id: "acc_RZPtest123" } },
    chefTransferPaise: 50,
  })
  assertEquals(plan.transferStatus, SKIP_TRANSFER_TOO_SMALL)
})

Deno.test("stamps trf_ ids from the Razorpay order response onto meal updates", () => {
  const plan = planRouteTransfers({
    cartItems: [{ mealId: "m1", quantity: 1 }],
    mealsById: { m1: meal },
    chefsById: { "chef-1": { gateway_account_id: "acc_RZPtest123" } },
    chefTransferPaise: 17000,
  })
  const withIds = applyTransferIdsToPlan(plan, {
    id: "order_1",
    transfers: [{ id: "trf_abc", account: "acc_RZPtest123" }],
  })
  assertEquals(withIds.mealUpdates[0].razorpayTransferId, "trf_abc")
  assertEquals(withIds.mealUpdates[0].transferStatus, TRANSFER_ON_HOLD)
})
