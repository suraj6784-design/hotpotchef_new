// supabase/functions/send-push-notification/index.ts
//
// FCM HTTP v1 path. Prefer this over legacy `push-notifier` when
// FIREBASE_SERVICE_ACCOUNT is configured.
//
// Invoked from `orders.status` via `handle_order_push_webhook`.
// Requires X-Webhook-Secret or the service role key — the anon JWT is rejected.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { GoogleAuth } from "npm:google-auth-library@9"
import { parseOrderStatus } from "../_shared/order_status.ts"
import { authorizeInternalInvoke, unauthorizedResponse } from "../_shared/webhook_auth.ts"

type NotifyTarget = { userId: string; title: string; body: string }

function collectTargets(record: Record<string, unknown>): NotifyTarget[] {
  const status = String(record.status ?? '')
  const kind = parseOrderStatus(status)
  const title = String(record.title ?? 'your order')
  const customerId = String(record.customer_id ?? '')
  const chefId = String(record.chef_id ?? '')
  const driverId = String(record.delivery_partner_id ?? record.driver_id ?? '')
  const targets: NotifyTarget[] = []

  const add = (userId: string, nTitle: string, nBody: string) => {
    if (userId) targets.push({ userId, title: nTitle, body: nBody })
  }

  if (kind === 'preparing' || kind === 'confirmed') {
    add(customerId, 'Chef is Cooking! 🍲', `Your order for ${title} is being prepared.`)
  } else if (kind === 'ready_for_pickup') {
    add(customerId, 'Ready for Pickup! 🥡', `Your ${title} is ready.`)
    add(driverId, 'Pickup ready 🛵', `${title} is ready for pickup.`)
  } else if (kind === 'out_for_delivery') {
    add(customerId, 'Order Out for Delivery! 🛵', `${title} is on its way to you.`)
    add(driverId, 'Delivery assigned 🛵', `You are delivering ${title}.`)
  } else if (kind === 'delivered' || kind === 'completed') {
    add(customerId, 'Enjoy Your Meal! 😋', 'Your order has been delivered.')
  } else if (kind === 'pending_chef_approval') {
    add(chefId, 'New Order Alert! 🔔', `New request for ${title}.`)
  } else if (customerId) {
    add(customerId, 'Order Update', `Your order status is now: ${status}`)
  }

  return targets
}

serve(async (req) => {
  try {
    const auth = authorizeInternalInvoke(req.headers)
    if (!auth.ok) return unauthorizedResponse(auth)

    const payload = await req.json()
    const record = payload.record ?? payload

    const targets = collectTargets(record)
    if (targets.length === 0) {
      return new Response(JSON.stringify({ message: 'No target user found in record' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const serviceAccountJson = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}')
    const auth = new GoogleAuth({
      credentials: serviceAccountJson,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    })
    const client = await auth.getClient()
    const accessToken = await client.getAccessToken()
    const projectId = serviceAccountJson.project_id

    const results = []
    for (const target of targets) {
      const { data: userData, error } = await supabaseAdmin
        .from('users')
        .select('fcm_token')
        .eq('id', target.userId)
        .maybeSingle()

      if (error || !userData?.fcm_token) {
        results.push({ userId: target.userId, skipped: 'no_fcm_token' })
        continue
      }

      const fcmRes = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${accessToken.token}`,
        },
        body: JSON.stringify({
          message: {
            token: userData.fcm_token,
            notification: { title: target.title, body: target.body },
            data: { order_id: String(record.id ?? ''), status: String(record.status ?? '') }
          }
        })
      })

      const fcmResult = await fcmRes.json()
      results.push({ userId: target.userId, fcmResult })
    }

    return new Response(JSON.stringify({ success: true, results }), { headers: { 'Content-Type': 'application/json' } })
  } catch (err) {
    return new Response(String(err?.message ?? err), { status: 500 })
  }
})
