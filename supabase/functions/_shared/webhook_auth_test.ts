import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts"
import { authorizeInternalInvoke, jwtRole } from "./webhook_auth.ts"

function headers(init: Record<string, string>): Headers {
  return new Headers(init)
}

const env: Record<string, string> = {
  EDGE_WEBHOOK_SECRET: "shared-secret",
  SUPABASE_SERVICE_ROLE_KEY: "service-role-jwt",
}

const getEnv = (key: string) => env[key]

Deno.test("rejects missing auth including anon-looking bearer", () => {
  const anon = authorizeInternalInvoke(headers({ authorization: "Bearer anon-key" }), getEnv)
  assertEquals(anon.ok, false)
  assertEquals(anon.status, 401)
})

Deno.test("accepts matching X-Webhook-Secret", () => {
  const ok = authorizeInternalInvoke(headers({ "x-webhook-secret": "shared-secret" }), getEnv)
  assertEquals(ok.ok, true)
})

Deno.test("accepts service role bearer", () => {
  const ok = authorizeInternalInvoke(headers({ authorization: "Bearer service-role-jwt" }), getEnv)
  assertEquals(ok.ok, true)
})

Deno.test("jwtRole reads service_role from payload", () => {
  const payload = btoa(JSON.stringify({ role: "service_role" }))
  const token = `header.${payload}.sig`
  assertEquals(jwtRole(token), "service_role")
  const ok = authorizeInternalInvoke(headers({ authorization: `Bearer ${token}` }), () => undefined)
  assertEquals(ok.ok, true)
})
