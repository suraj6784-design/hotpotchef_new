// supabase/functions/create-chef-account/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const { chef_id, email, name, phone } = await req.json()

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Check if chef already has a gateway account ID
    const { data: userData } = await supabaseAdmin
      .from('users')
      .select('gateway_account_id')
      .eq('id', chef_id)
      .single()

    if (userData?.gateway_account_id) {
      return new Response(JSON.stringify({ success: true, account_id: userData.gateway_account_id }), {
        headers: { 'Content-Type': 'application/json' }
      })
    }

    // 🌟 MOCK FALLBACK FOR TESTING:
    // Since Razorpay Route is not active on your account yet, 
    // we generate a realistic test-account ID so you can proceed with building/testing.
    const mockAccountId = `acc_mock_${Date.now()}`

    // Save the mock account ID to the chef's user record
    await supabaseAdmin.from('users').update({
      gateway_account_id: mockAccountId,
      payout_enabled: true
    }).eq('id', chef_id)

    return new Response(JSON.stringify({ success: true, account_id: mockAccountId }), {
      headers: { 'Content-Type': 'application/json' }
    })

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 400, headers: { 'Content-Type': 'application/json' } })
  }
})