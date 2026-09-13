import { assertEquals, assertExists } from "https://deno.land/std@0.224.0/assert/mod.ts"
import { handleCreateChefAccount } from "./handler.mjs"
import { createRouteLinkedAccount } from "./razorpay_accounts.mjs"

const chefId = "11111111-1111-1111-1111-111111111111"

function post(body: Record<string, unknown>, headers: Record<string, string> = {}) {
  return new Request("http://localhost/create-chef-account", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  })
}

async function read(response: Response) {
  return { status: response.status, body: await response.json() }
}

function chefDeps(overrides: Record<string, unknown> = {}) {
  return {
    async getUser(token: string) {
      if (token !== "valid-chef-jwt") return null
      return { id: chefId, user_metadata: { role: "Chef" } }
    },
    async findCallerRow() {
      return { gateway_account_id: null, role: "Chef" }
    },
    async enablePayout() {},
    now: () => 1700000000000,
    ...overrides,
  }
}

const bankBody = {
  chef_id: chefId,
  email: "chef@example.com",
  name: "Test Kitchen",
  phone: "9999999999",
  bank_account: "123456789012",
  ifsc_code: "HDFC0001234",
  beneficiary_name: "Test Kitchen",
}

Deno.test("missing Razorpay keys take the labeled mock path", async () => {
  const updates: { id: string; accountId: string }[] = []
  const result = await read(
    await handleCreateChefAccount(
      post(bankBody, { Authorization: "Bearer valid-chef-jwt" }),
      chefDeps({
        getRazorpayKeys: () => ({ keyId: "", keySecret: "" }),
        async enablePayout(id: string, accountId: string) {
          updates.push({ id, accountId })
        },
      }),
    ),
  )

  assertEquals(result.status, 200)
  assertEquals(result.body.mock, true)
  assertEquals(result.body.mode, "mock")
  assertEquals(result.body.account_id, "acc_mock_1700000000000")
  assertEquals(updates[0].accountId.startsWith("acc_mock_"), true)
})

Deno.test("Test keys POST the v2 Route linked-account API shapes", async () => {
  const calls: { method: string; url: string; body: Record<string, unknown> | null }[] = []
  const fetchImpl = (url: string, init?: RequestInit) => {
    const body = init?.body ? JSON.parse(String(init.body)) : null
    calls.push({ method: String(init?.method), url, body })
    if (url.endsWith("/v2/accounts") && init?.method === "POST") {
      return Promise.resolve(
        new Response(JSON.stringify({ id: "acc_RZPv2Chef" }), { status: 200 }),
      )
    }
    if (url.endsWith("/products") && init?.method === "POST") {
      return Promise.resolve(
        new Response(JSON.stringify({ id: "acc_prd_route1" }), { status: 200 }),
      )
    }
    if (url.includes("/products/") && init?.method === "PATCH") {
      return Promise.resolve(
        new Response(JSON.stringify({ id: "acc_prd_route1", activation_status: "activated" }), {
          status: 200,
        }),
      )
    }
    return Promise.resolve(new Response(JSON.stringify({ error: { description: "unexpected" } }), { status: 500 }))
  }

  const created = await createRouteLinkedAccount(bankBody, {
    keyId: "rzp_test_abc",
    keySecret: "test_secret",
    fetchImpl,
  })

  assertEquals(created.accountId, "acc_RZPv2Chef")
  assertEquals(created.mock, false)
  assertEquals(created.mode, "test")
  assertEquals(created.api, "v2")
  assertEquals(calls[0].url, "https://api.razorpay.com/v2/accounts")
  assertEquals(calls[0].body?.type, "route")
  assertEquals(calls[0].body?.business_type, "individual")
  assertEquals(calls[0].body?.email, "chef@example.com")
  assertEquals(calls[1].body?.product_name, "route")
  assertEquals(calls[1].body?.tnc_accepted, true)
  assertExists(calls[2].body?.settlements)
  assertEquals((calls[2].body?.settlements as { ifsc_code: string }).ifsc_code, "HDFC0001234")
})

Deno.test("handler with Test keys persists the real acc_ id and never acc_mock_*", async () => {
  const updates: { id: string; accountId: string }[] = []
  const fetchImpl = (url: string, init?: RequestInit) => {
    if (String(url).endsWith("/v2/accounts")) {
      return Promise.resolve(new Response(JSON.stringify({ id: "acc_FromHandler" }), { status: 200 }))
    }
    if (String(url).includes("/products") && init?.method === "POST") {
      return Promise.resolve(new Response(JSON.stringify({ id: "acc_prd_1" }), { status: 200 }))
    }
    return Promise.resolve(new Response(JSON.stringify({ id: "acc_prd_1" }), { status: 200 }))
  }

  const result = await read(
    await handleCreateChefAccount(
      post(bankBody, { Authorization: "Bearer valid-chef-jwt" }),
      chefDeps({
        getRazorpayKeys: () => ({ keyId: "rzp_test_abc", keySecret: "secret" }),
        createLinkedAccount: (input: Record<string, unknown>, keys: { keyId: string; keySecret: string }) =>
          createRouteLinkedAccount(input, { ...keys, fetchImpl }),
        async enablePayout(id: string, accountId: string) {
          updates.push({ id, accountId })
        },
      }),
    ),
  )

  assertEquals(result.status, 200)
  assertEquals(result.body.account_id, "acc_FromHandler")
  assertEquals(result.body.mock, false)
  assertEquals(result.body.mode, "test")
  assertEquals(String(result.body.account_id).startsWith("acc_mock_"), false)
  assertEquals(updates[0].accountId, "acc_FromHandler")
})

Deno.test("v2 URL-not-found falls back to POST /v1/beta/accounts with bank_account", async () => {
  const calls: string[] = []
  const fetchImpl = (url: string, init?: RequestInit) => {
    calls.push(`${init?.method} ${url}`)
    if (url.endsWith("/v2/accounts")) {
      return Promise.resolve(
        new Response(
          JSON.stringify({ error: { description: "The requested URL was not found on the server." } }),
          { status: 400 },
        ),
      )
    }
    if (url.endsWith("/v1/beta/accounts")) {
      const body = JSON.parse(String(init?.body))
      assertEquals(body.bank_account.account_number, "123456789012")
      assertEquals(body.tnc_accepted, true)
      return Promise.resolve(new Response(JSON.stringify({ id: "acc_LegacyBeta" }), { status: 200 }))
    }
    return Promise.resolve(new Response("{}", { status: 500 }))
  }

  const created = await createRouteLinkedAccount(bankBody, {
    keyId: "rzp_test_abc",
    keySecret: "secret",
    fetchImpl,
  })
  assertEquals(created.accountId, "acc_LegacyBeta")
  assertEquals(created.api, "v1_beta")
  assertEquals(calls[1], "POST https://api.razorpay.com/v1/beta/accounts")
})
