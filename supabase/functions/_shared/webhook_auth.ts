// Internal Edge Function auth for DB webhooks / cron-style invokes.
// Gateway `verify_jwt` is not enough: the publishable/anon key is a valid JWT
// and live probes showed send-push / release-chef-payout returning 200 with it.
//
// Accept:
//   1. X-Webhook-Secret matching EDGE_WEBHOOK_SECRET (or WEBHOOK_SECRET)
//   2. Bearer token equal to SUPABASE_SERVICE_ROLE_KEY
//   3. Bearer JWT with role `service_role`
// Reject everything else, including anon / authenticated user JWTs.

export type EnvReader = (key: string) => string | undefined

export interface AuthResult {
  ok: boolean
  status: number
  error?: string
}

export function extractBearerToken(authorizationHeader: string | null | undefined): string | null {
  if (!authorizationHeader) return null
  const match = authorizationHeader.match(/^Bearer\s+(\S+)/i)
  return match?.[1] ?? null
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

export function jwtRole(token: string): string | null {
  try {
    const parts = token.split(".")
    if (parts.length < 2) return null
    const payload = parts[1].replace(/-/g, "+").replace(/_/g, "/")
    const pad = payload.length % 4 === 0 ? "" : "=".repeat(4 - (payload.length % 4))
    const json = JSON.parse(atob(payload + pad)) as {
      role?: unknown
      app_metadata?: { role?: unknown }
    }
    const role = json.role ?? json.app_metadata?.role
    return role == null ? null : String(role)
  } catch {
    return null
  }
}

export function authorizeInternalInvoke(
  headers: Headers,
  getEnv: EnvReader = (key) => Deno.env.get(key),
): AuthResult {
  const shared = (getEnv("EDGE_WEBHOOK_SECRET") ?? getEnv("WEBHOOK_SECRET") ?? "").trim()
  const headerSecret = (headers.get("x-webhook-secret") ?? "").trim()
  if (shared && headerSecret && timingSafeEqual(shared, headerSecret)) {
    return { ok: true, status: 200 }
  }

  const bearer = extractBearerToken(headers.get("authorization"))
  const serviceKey = (getEnv("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim()
  if (bearer && serviceKey && timingSafeEqual(bearer, serviceKey)) {
    return { ok: true, status: 200 }
  }
  if (bearer && jwtRole(bearer) === "service_role") {
    return { ok: true, status: 200 }
  }

  return { ok: false, status: 401, error: "Unauthorized" }
}

export function unauthorizedResponse(result: AuthResult): Response {
  return new Response(JSON.stringify({ success: false, error: result.error ?? "Unauthorized" }), {
    status: result.status || 401,
    headers: { "Content-Type": "application/json" },
  })
}
