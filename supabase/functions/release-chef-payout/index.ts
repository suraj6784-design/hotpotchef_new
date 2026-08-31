// supabase/functions/release-chef-payout/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const payload = await req.json()
    const record = payload.record // Triggered by DB Webhook on meals table update

    // Only process if status changed to 'Delivered' and transfer is pending release
    if (!record || record.status !== 'Delivered' || record.transfer_status === 'released') {
      return new Response(JSON.stringify({ skipped: true }), { headers: { 'Content-Type': 'application/json' } })
    }

    const transferId = record.razorpay_transfer_id
    if (!transferId) {
      throw new Error('No Razorpay Transfer ID found for this order record.')
    }

    const razorpayKeyId = Deno.env.get('RAZORPAY_KEY_ID')
    const razorpayKeySecret = Deno.env.get('RAZORPAY_KEY_SECRET')
    const authHeader = btoa(`${razorpayKeyId}:${razorpayKeySecret}`)

    // Call Razorpay API to release the hold
    const rzpResponse = await fetch(`https://api.razorpay.com/v1/transfers/${transferId}`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Basic ${authHeader}`
      },
      body: JSON.stringify({
        on_hold: 0 // 👈 Releases funds to chef's linked bank account
      })
    })

    const rzpResult = await rzpResponse.json()
    if (!rzpResponse.ok) {
      throw new Error(rzpResult.error?.description || 'Failed to release transfer hold on Razorpay')
    }

    // Update database status to released
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    await supabaseAdmin.from('meals')
      .update({ transfer_status: 'released' })
      .eq('id', record.id)

    return new Response(JSON.stringify({ success: true, transfer_id: transferId, rzpResult }), {
      headers: { 'Content-Type': 'application/json' }
    })

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 400, headers: { 'Content-Type': 'application/json' } })
  }
})