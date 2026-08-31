// supabase/functions/create-split-order/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const { 
      meal_id, 
      customer_email, 
      total_amount // Accept the exact final grand total calculated by the frontend
    } = await req.json()

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    if (!total_amount || isNaN(total_amount)) {
      throw new Error('Invalid total amount provided')
    }

    const finalOrderAmount = Number(total_amount)
    const totalAmountInPaise = Math.round(finalOrderAmount * 100)
    
    const platformCommission = Math.round(finalOrderAmount * 0.15 * 100) // in paisa
    const chefTransferAmount = Math.round(finalOrderAmount * 100) - platformCommission

    console.log("Authoritative Grand Total Received from App (INR):", finalOrderAmount);
    console.log("Total Amount Sent to Razorpay (Paise):", totalAmountInPaise);

    // Create Standard Razorpay Order
    const razorpayKeyId = Deno.env.get('RAZORPAY_KEY_ID')
    const razorpayKeySecret = Deno.env.get('RAZORPAY_KEY_SECRET')
    const authHeader = btoa(`${razorpayKeyId}:${razorpayKeySecret}`)

    const rzpResponse = await fetch('https://api.razorpay.com/v1/orders', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Basic ${authHeader}`
      },
      body: JSON.stringify({
        amount: totalAmountInPaise,
        currency: 'INR',
        receipt: `rcpt_${Date.now()}`
      })
    })

    const rzpOrder = await rzpResponse.json()
    if (!rzpResponse.ok) throw new Error(rzpOrder.error?.description || 'Razorpay order creation failed')

    // Save breakdown parameters in your DB meal record
    await supabaseAdmin.from('meals').update({
      platform_fee: platformCommission / 100,
      chef_payout_amount: chefTransferAmount / 100,
      order_id: rzpOrder.id,
      transfer_status: 'skipped_standard_mode'
    }).eq('id', meal_id)

    return new Response(JSON.stringify({ 
      success: true, 
      order_id: rzpOrder.id,
      amount: totalAmountInPaise,
      currency: 'INR',
      chef_transfer: chefTransferAmount
    }), { 
      headers: { 'Content-Type': 'application/json' } 
    })

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), { status: 400, headers: { 'Content-Type': 'application/json' } })
  }
})