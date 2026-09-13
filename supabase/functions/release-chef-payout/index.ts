// supabase/functions/release-chef-payout/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { handleReleaseChefPayout } from "./handler.ts"

serve(async (req) => {
  try {
    const payload = await req.json()
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    )

    const result = await handleReleaseChefPayout(payload, {
      async markReleased(mealId, transferId) {
        await supabaseAdmin.from("meals")
          .update({ transfer_status: "released", razorpay_transfer_id: transferId })
          .eq("id", mealId)
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
