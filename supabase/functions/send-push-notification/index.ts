// supabase/functions/send-push-notification/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { GoogleAuth } from "npm:google-auth-library@9"

serve(async (req) => {
  try {
    const { record } = await req.json()
    
    // Since customer_name stores the customer's email/identifier, use it to find user
    const customerEmail = record.customer_name
    const chefId = record.chef_id

    if (!customerEmail && !chefId) {
      return new Response('No target user found in record', { status: 400 })
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Find the target user's FCM token (checking customer by email, or fallback to chef by id)
    let query = supabaseAdmin.from('users').select('fcm_token')
    if (customerEmail) {
      query = query.eq('email', customerEmail)
    } else {
      query = query.eq('id', chefId)
    }

    const { data: userData, error } = await query.maybeSingle()

    if (error || !userData?.fcm_token) {
      return new Response('FCM token not found for user', { status: 404 })
    }

    // Authenticate with Google using the Service Account Secret
    const serviceAccountJson = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}')
    const auth = new GoogleAuth({
      credentials: serviceAccountJson,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    })
    const client = await auth.getClient()
    const accessToken = await client.getAccessToken()

    // Construct Notification Payload
    let title = 'Order Update'
    let body = `Your order status is now: ${record.status}`

    if (record.status === 'Preparing') {
      title = 'Chef is Cooking! 🍲'
      body = `Your order for ${record.title} is being prepared.`
    } else if (record.status === 'Out for Delivery') {
      title = 'Order Out for Delivery! 🛵'
      body = `${record.title} is on its way to you.`
    } else if (record.status === 'Delivered') {
      title = 'Enjoy Your Meal! 😋'
      body = 'Your order has been delivered.'
    }

    // Send via FCM v1 API
    const projectId = serviceAccountJson.project_id
    const fcmRes = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${accessToken.token}`,
      },
      body: JSON.stringify({
        message: {
          token: userData.fcm_token,
          notification: { title, body },
          data: { order_id: record.id.toString(), status: record.status }
        }
      })
    })

    const fcmResult = await fcmRes.json()
    return new Response(JSON.stringify({ success: true, fcmResult }), { headers: { 'Content-Type': 'application/json' } })
  } catch (err) {
    return new Response(String(err?.message ?? err), { status: 500 })
  }
})

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/send-push-notification' \
    --header 'apiKey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH' \
    --data '{"name":"Functions"}'

*/
