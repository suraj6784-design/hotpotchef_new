import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts"
import { handleCreateSplitOrder } from "./handler.ts"

function post(body: Record<string, unknown>, headers: Record<string, string> = {}) {
  return new Request("http://localhost/create-split-order", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer test-jwt",
      ...headers,
    },
    body: JSON.stringify(body),
  })
}

async function read(response: Response) {
  return { status: response.status, body: await response.json() }
}

function baseDeps(overrides: Record<string, unknown> = {}) {
  return {
    getRazorpayKeys: () => ({ keyId: "rzp_test_abc", keySecret: "secret" }),
    now: () => 1700000000000,
    async getUser() {
      return { id: "customer-1" }
    },
    async fetchMealsById() {
      return { m1: { id: "m1", chef_id: "chef-1", price: 200 } }
    },
    async fetchRpcCartTotal() {
      return null
    },
    async fetchCoinBalance() {
      return 0
    },
    async fetchChefsById() {
      return { "chef-1": { gateway_account_id: "acc_RZPtest123" } }
    },
    async persistMealPayments() {},
    ...overrides,
  }
}

Deno.test("create-split-order attaches Route transfers when a real account exists", async () => {
  let orderBody: Record<string, unknown> | null = null
  const persisted: Record<string, unknown>[] = []
  const result = await read(
    await handleCreateSplitOrder(
      post({ cart_items: [{ mealId: "m1", quantity: 1 }], delivery_fee: 0, tip_amount: 0 }),
      baseDeps({
        fetchImpl: (url: string, init?: RequestInit) => {
          assertEquals(url, "https://api.razorpay.com/v1/orders")
          orderBody = JSON.parse(String(init?.body))
          return Promise.resolve(
            new Response(
              JSON.stringify({
                id: "order_route_1",
                transfers: [{ id: "trf_1", account: "acc_RZPtest123" }],
              }),
              { status: 200 },
            ),
          )
        },
        persistMealPayments: (_ids: string[], fields: { updates: { transferStatus: string; razorpayTransferId?: string }[] }) => {
          persisted.push(fields)
        },
      }),
    ),
  )

  assertEquals(result.status, 200)
  assertEquals(result.body.order_id, "order_route_1")
  assertEquals(result.body.transfer_status, "on_hold")
  const attached = (orderBody as { transfers?: { account: string }[] } | null)?.transfers
  assertEquals(attached?.[0].account, "acc_RZPtest123")
  assertEquals((persisted[0] as { updates: { transferStatus: string }[] }).updates[0].transferStatus, "on_hold")
})

Deno.test("create-split-order skips Route (not silently standard) for mock chef accounts", async () => {
  let orderBody: Record<string, unknown> | null = null
  const result = await read(
    await handleCreateSplitOrder(
      post({ cart_items: [{ mealId: "m1", quantity: 1 }] }),
      baseDeps({
        fetchChefsById: async () => ({ "chef-1": { gateway_account_id: "acc_mock_1" } }),
        fetchImpl: (_url: string, init?: RequestInit) => {
          orderBody = JSON.parse(String(init?.body))
          return Promise.resolve(new Response(JSON.stringify({ id: "order_skip_1" }), { status: 200 }))
        },
      }),
    ),
  )

  assertEquals(result.status, 200)
  assertEquals(result.body.transfer_status, "skipped_mock_account")
  assertEquals((orderBody as { transfers?: unknown } | null)?.transfers, undefined)
})

Deno.test("create-split-order returns 401 when the user JWT is missing", async () => {
  const noAuth = new Request("http://localhost/create-split-order", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ cart_items: [{ mealId: "m1", quantity: 1 }] }),
  })
  const result = await read(await handleCreateSplitOrder(noAuth, baseDeps()))
  assertEquals(result.status, 401)
  assertEquals(result.body.error, "Authentication required")
})

Deno.test("create-split-order returns 401 when the user JWT is invalid", async () => {
  const result = await read(
    await handleCreateSplitOrder(
      post({ cart_items: [{ mealId: "m1", quantity: 1 }] }),
      baseDeps({
        getUser: async () => null,
      }),
    ),
  )
  assertEquals(result.status, 401)
  assertEquals(result.body.error, "Invalid or expired session")
})

Deno.test("create-split-order still requires Razorpay keys for the parent order", async () => {
  const result = await read(
    await handleCreateSplitOrder(
      post({ cart_items: [{ mealId: "m1", quantity: 1 }] }),
      baseDeps({
        getRazorpayKeys: () => ({ keyId: "", keySecret: "" }),
      }),
    ),
  )
  assertEquals(result.status, 400)
  assertEquals(result.body.error, "Payment gateway configuration missing")
})
