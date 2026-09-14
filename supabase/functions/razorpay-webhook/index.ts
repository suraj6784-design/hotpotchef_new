// Razorpay Dashboard webhook.
//
// Env:
//   RAZORPAY_WEBHOOK_SECRET  — required. Dashboard → Webhooks → Secret.
//   Unsigned / invalid / missing-secret requests return HTTP 401 (not 500).
//
// This function verifies the HMAC and acknowledges the event. Checkout still
// finalizes via place_customer_order after Razorpay Checkout success. Do not
// invent a second order-insert path here.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { verifyRazorpaySignature } from "./signature.ts"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-razorpay-signature",
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ success: false, error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  }

  const rawBody = await req.text()
  const secret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET") ?? ""
  const verified = await verifyRazorpaySignature(
    secret,
    rawBody,
    req.headers.get("x-razorpay-signature"),
  )
  if (!verified.ok) {
    return new Response(JSON.stringify({ success: false, error: verified.error }), {
      status: verified.status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  }

  let event = "unknown"
  try {
    const payload = JSON.parse(rawBody) as { event?: unknown }
    if (payload.event != null) event = String(payload.event)
  } catch {
    event = "unparsed"
  }

  return new Response(
    JSON.stringify({ success: true, received: true, event }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  )
})
