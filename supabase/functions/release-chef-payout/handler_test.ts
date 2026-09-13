import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts"
import { firstTransferIdFromOrder, handleReleaseChefPayout } from "./handler.ts"

Deno.test("skips release when checkout recorded a skipped_* transfer_status", async () => {
  const result = await handleReleaseChefPayout(
    { record: { id: "m1", status: "Delivered", transfer_status: "skipped_mock_account" } },
    { async markReleased() {} },
  )
  assertEquals(result.status, 200)
  assertEquals(result.body.skipped, true)
  assertEquals(result.body.reason, "skipped_mock_account")
})

Deno.test("skips when the meal is not delivered", async () => {
  const result = await handleReleaseChefPayout(
    { record: { id: "m1", status: "Accepted", transfer_status: "on_hold", razorpay_transfer_id: "trf_1" } },
    { async markReleased() {} },
  )
  assertEquals(result.body.reason, "not_delivered")
})

Deno.test("releases an on-hold transfer with PATCH /v1/transfers/:id", async () => {
  const calls: { method?: string; url: string; body: unknown }[] = []
  let marked = ""
  const result = await handleReleaseChefPayout(
    {
      record: {
        id: "m1",
        status: "Delivered",
        transfer_status: "on_hold",
        razorpay_transfer_id: "trf_abc",
      },
    },
    {
      getRazorpayKeys: () => ({ keyId: "rzp_test_abc", keySecret: "secret" }),
      fetchImpl: (input: string | URL | Request, init?: RequestInit) => {
        calls.push({
          method: init?.method,
          url: String(input),
          body: init?.body ? JSON.parse(String(init.body)) : null,
        })
        return Promise.resolve(new Response(JSON.stringify({ id: "trf_abc", on_hold: false }), { status: 200 }))
      },
      async markReleased(mealId, transferId) {
        marked = `${mealId}:${transferId}`
      },
    },
  )

  assertEquals(result.status, 200)
  assertEquals(result.body.success, true)
  assertEquals(result.body.transfer_id, "trf_abc")
  assertEquals(calls[0].url, "https://api.razorpay.com/v1/transfers/trf_abc")
  assertEquals(calls[0].body, { on_hold: 0 })
  assertEquals(marked, "m1:trf_abc")
})

Deno.test("looks up trf_ from the Razorpay order when meals only stored order_id", async () => {
  const result = await handleReleaseChefPayout(
    {
      record: {
        id: "m1",
        status: "Delivered",
        transfer_status: "on_hold",
        order_id: "order_1",
      },
    },
    {
      getRazorpayKeys: () => ({ keyId: "rzp_test_abc", keySecret: "secret" }),
      fetchImpl: (input: string | URL | Request, init?: RequestInit) => {
        if (String(input).includes("/v1/orders/order_1")) {
          return Promise.resolve(
            new Response(
              JSON.stringify({ id: "order_1", transfers: [{ id: "trf_from_order", account: "acc_1" }] }),
              { status: 200 },
            ),
          )
        }
        assertEquals(init?.method, "PATCH")
        return Promise.resolve(new Response(JSON.stringify({ id: "trf_from_order" }), { status: 200 }))
      },
      async markReleased() {},
    },
  )
  assertEquals(result.body.transfer_id, "trf_from_order")
})

Deno.test("parses the first trf_ id from an expanded order", () => {
  assertEquals(
    firstTransferIdFromOrder({ transfers: [{ account: "acc_1" }, { id: "trf_x", account: "acc_1" }] }),
    "trf_x",
  )
})

Deno.test("errors when keys are missing and a real transfer is pending", async () => {
  const result = await handleReleaseChefPayout(
    { record: { id: "m1", status: "Delivered", transfer_status: "on_hold", razorpay_transfer_id: "trf_1" } },
    {
      getRazorpayKeys: () => ({ keyId: "", keySecret: "" }),
      async markReleased() {},
    },
  )
  assertEquals(result.status, 400)
  assertEquals(result.body.error, "Payment gateway configuration missing")
})
