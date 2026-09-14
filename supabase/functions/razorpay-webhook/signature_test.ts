import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts"
import { hmacSha256Hex, verifyRazorpaySignature } from "./signature.ts"

Deno.test("missing webhook secret is 401, not 500", async () => {
  const result = await verifyRazorpaySignature("", "{}", "abc")
  assertEquals(result.status, 401)
  assertEquals(result.error, "Webhook secret is not configured")
})

Deno.test("unsigned payload is 401", async () => {
  const result = await verifyRazorpaySignature("whsec", "{}", null)
  assertEquals(result.status, 401)
  assertEquals(result.error, "Missing Razorpay signature")
})

Deno.test("invalid signature is 401", async () => {
  const result = await verifyRazorpaySignature("whsec", "{\"event\":\"payment.captured\"}", "deadbeef")
  assertEquals(result.status, 401)
  assertEquals(result.error, "Invalid Razorpay signature")
})

Deno.test("valid HMAC SHA256 hex is accepted", async () => {
  const body = "{\"event\":\"payment.captured\"}"
  const sig = await hmacSha256Hex("whsec", body)
  const result = await verifyRazorpaySignature("whsec", body, sig)
  assertEquals(result.ok, true)
  assertEquals(result.status, 200)
})
