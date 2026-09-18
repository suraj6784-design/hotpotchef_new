import { filterSellableMeals } from "../_shared/meal_catalog.ts"

export async function hmacSha256Hex(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  )
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body))
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("")
}

export function timingSafeEqual(a: string, b: string): boolean {
  const encoder = new TextEncoder()
  const aa = encoder.encode(a)
  const bb = encoder.encode(b)
  const len = Math.max(aa.length, bb.length)
  let diff = aa.length ^ bb.length
  for (let i = 0; i < len; i++) {
    diff |= (aa[i] ?? 0) ^ (bb[i] ?? 0)
  }
  return diff === 0
}

export async function verifyRazorpaySignature(
  secret: string,
  rawBody: string,
  headerSignature: string | null,
): Promise<{ ok: boolean; status: number; error?: string }> {
  const configured = secret.trim()
  if (!configured) {
    // Fail closed. 503 (not 500): the function booted, but ops has not set
    // RAZORPAY_WEBHOOK_SECRET. Client unsigned/invalid signatures stay 401.
    return { ok: false, status: 503, error: "Webhook secret is not configured" }
  }
  const provided = (headerSignature ?? "").trim()
  if (!provided) {
    return { ok: false, status: 401, error: "Missing Razorpay signature" }
  }
  const expected = await hmacSha256Hex(configured, rawBody)
  if (!timingSafeEqual(expected, provided)) {
    return { ok: false, status: 401, error: "Invalid Razorpay signature" }
  }
  return { ok: true, status: 200 }
}

export { filterSellableMeals }
