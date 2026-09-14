// supabase/functions/release-chef-payout/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { handleReleaseChefPayout } from "./handler.ts"
import { authorizeInternalInvoke, unauthorizedResponse } from "../_shared/webhook_auth.ts"

serve(async (req) => {
  try {
    const auth = authorizeInternalInvoke(req.headers)
    if (!auth.ok) return unauthorizedResponse(auth)

    const payload = await req.json()
    const record = payload.record ?? {}
    const table = String(payload.table ?? "")
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    )

    const result = await handleReleaseChefPayout(payload, {
      async markReleased(rowId, transferId) {
        const isOrder = table === "orders" || !!record.customer_id || !!record.razorpay_order_id
        if (isOrder) {
          await supabaseAdmin.from("orders")
            .update({
              payout_status: "released",
              razorpay_transfer_id: transferId,
              payout_released_at: new Date().toISOString(),
            })
            .eq("id", rowId)
          const rzpOrder = record.razorpay_order_id ?? record.order_id
          if (rzpOrder) {
            await supabaseAdmin.from("meals")
              .update({ transfer_status: "released", razorpay_transfer_id: transferId })
              .eq("order_id", rzpOrder)
          }
          return
        }
        await supabaseAdmin.from("meals")
          .update({ transfer_status: "released", razorpay_transfer_id: transferId })
          .eq("id", rowId)
      },
    })

    return new Response(JSON.stringify(result.body), {
      status: result.status,
      headers: { "Content-Type": "application/json" },
    })
  } catch (err) {
    const message = err instanceof Error ? err.message : "Bad request"
    return new Response(JSON.stringify({ error: message }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    })
  }
})
