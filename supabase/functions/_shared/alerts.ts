import { GoogleAuth } from 'npm:google-auth-library@9'
import { type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

type OrderAlert = {
  title: string
  body: string
  notifyChef: boolean
  notifyCustomer: boolean
}

function mealTitleFromItems(items: unknown): string {
  let parsed: unknown = items
  if (typeof items === 'string' && items.trim()) {
    try {
      parsed = JSON.parse(items)
    } catch {
      parsed = items
    }
  }
  if (Array.isArray(parsed) && parsed.length > 0 && parsed[0] && typeof parsed[0] === 'object') {
    const row = parsed[0] as Record<string, unknown>
    const title = row.title ?? row.name ?? row.meal_name
    if (typeof title === 'string' && title.trim()) return title.trim()
  }
  return 'your order'
}

export function orderAlertCopy(opts: {
  status: string
  isInsert: boolean
  previousStatus?: string | null
  mealTitle?: string
}): OrderAlert | null {
  const current = (opts.status || '').trim().toLowerCase()
  const previous = (opts.previousStatus || '').trim().toLowerCase()
  if (!opts.isInsert && current === previous) return null
  const mealTitle = opts.mealTitle || 'your order'

  if (opts.isInsert || current.includes('pending')) {
    return {
      title: 'New order',
      body: `You have a new order for ${mealTitle}.`,
      notifyChef: true,
      notifyCustomer: false,
    }
  }
  if (current.includes('cancel')) {
    return {
      title: 'Order cancelled',
      body: `The order for ${mealTitle} was cancelled. A refund is issued if you paid online.`,
      notifyChef: true,
      notifyCustomer: true,
    }
  }
  if (current.includes('deliver') || current.includes('complet')) {
    return {
      title: 'Order delivered',
      body: 'Your order has arrived. Rate the kitchen when you can.',
      notifyChef: false,
      notifyCustomer: true,
    }
  }
  if (current.includes('out for delivery') || current.includes('out_for_delivery')) {
    return {
      title: 'On the way',
      body: `${mealTitle} is out for delivery. Track it from Orders.`,
      notifyChef: false,
      notifyCustomer: true,
    }
  }
  if (current.includes('assign')) {
    return {
      title: 'Delivery partner assigned',
      body: 'A delivery partner is on the way to the kitchen.',
      notifyChef: false,
      notifyCustomer: true,
    }
  }
  if (current.includes('ready')) {
    return {
      title: 'Order ready',
      body: `${mealTitle} is ready for pickup.`,
      notifyChef: false,
      notifyCustomer: true,
    }
  }
  if (current.includes('prepar') || current.includes('confirm')) {
    return {
      title: 'Order confirmed',
      body: `Your order for ${mealTitle} is being prepared.`,
      notifyChef: false,
      notifyCustomer: true,
    }
  }
  return null
}

async function sendFcm(token: string, title: string, body: string, data: Record<string, string>) {
  const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}'
  const serviceAccountJson = JSON.parse(raw)
  const projectId = serviceAccountJson.project_id
  if (!projectId || !token) return

  const auth = new GoogleAuth({
    credentials: serviceAccountJson,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  })
  const client = await auth.getClient()
  const accessToken = await client.getAccessToken()

  await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken.token}`,
    },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        data,
      },
    }),
  })
}

async function sendEmail(to: string | null | undefined, subject: string, text: string) {
  const key = Deno.env.get('RESEND_API_KEY')
  const from = Deno.env.get('ALERTS_FROM_EMAIL') || Deno.env.get('SUPPORT_EMAIL') || ''
  if (!key || !to || !from) return
  await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from, to: [to], subject, text }),
  })
}

async function notifyUser(
  admin: SupabaseClient,
  userId: string | null | undefined,
  title: string,
  body: string,
  data: Record<string, string>,
) {
  if (!userId) return
  const { data: user } = await admin
    .from('users')
    .select('fcm_token, email')
    .eq('id', userId)
    .maybeSingle()
  if (user?.fcm_token) {
    try {
      await sendFcm(String(user.fcm_token), title, body, data)
    } catch (err) {
      console.error('FCM send failed', err)
    }
  }
  try {
    await sendEmail(user?.email, title, body)
  } catch (err) {
    console.error('Email send skipped', err)
  }
}

export async function dispatchOrderAlert(
  admin: SupabaseClient,
  orderId: string,
  opts: { isInsert: boolean; previousStatus?: string | null },
) {
  const { data: order } = await admin
    .from('orders')
    .select('id, status, items, chef_id, customer_id')
    .eq('id', orderId)
    .maybeSingle()
  if (!order) return { sent: 0 }

  const copy = orderAlertCopy({
    status: String(order.status ?? ''),
    isInsert: opts.isInsert,
    previousStatus: opts.previousStatus,
    mealTitle: mealTitleFromItems(order.items),
  })
  if (!copy) return { sent: 0 }

  const data = { order_id: String(order.id), status: String(order.status ?? ''), alert_id: `${order.id}-${order.status}` }
  const targets: string[] = []
  if (copy.notifyChef && order.chef_id) targets.push(String(order.chef_id))
  if (copy.notifyCustomer && order.customer_id) targets.push(String(order.customer_id))

  for (const userId of [...new Set(targets)]) {
    await notifyUser(admin, userId, copy.title, copy.body, data)
  }
  return { sent: targets.length, title: copy.title }
}

function orderGroupTitle(roomId: string) {
  const label = roomId.length > 8 ? roomId.slice(0, 8).toUpperCase() : roomId.toUpperCase()
  return `Order ${label}`
}

export async function dispatchChatAlert(admin: SupabaseClient, messageId: string) {
  const { data: message } = await admin
    .from('messages')
    .select('id, meal_id, sender_id, content')
    .eq('id', messageId)
    .maybeSingle()
  if (!message) return { sent: 0 }

  const recipients = new Set<string>()
  const mealId = message.meal_id as string | null
  let title = 'New message'
  if (mealId) {
    const { data: order } = await admin
      .from('orders')
      .select('customer_id, user_id, chef_id, driver_id, delivery_partner_id')
      .eq('id', mealId)
      .maybeSingle()
    if (order) {
      title = orderGroupTitle(mealId)
      for (const key of ['customer_id', 'user_id', 'chef_id', 'driver_id', 'delivery_partner_id'] as const) {
        if (order[key]) recipients.add(String(order[key]))
      }
    } else {
      const { data: request } = await admin
        .from('customer_requests')
        .select('customer_id, accepted_chef_id')
        .eq('id', mealId)
        .maybeSingle()
      if (request) {
        title = 'Catering chat'
        if (request.customer_id) recipients.add(String(request.customer_id))
        if (request.accepted_chef_id) recipients.add(String(request.accepted_chef_id))
      } else {
        const { data: meal } = await admin.from('meals').select('chef_id').eq('id', mealId).maybeSingle()
        if (meal?.chef_id) recipients.add(String(meal.chef_id))

        const { data: peers } = await admin
          .from('messages')
          .select('sender_id')
          .eq('meal_id', mealId)
          .neq('sender_id', message.sender_id)
          .limit(20)
        for (const row of peers ?? []) {
          if (row.sender_id) recipients.add(String(row.sender_id))
        }
      }
    }
  }
  recipients.delete(String(message.sender_id ?? ''))

  const preview = String(message.content ?? '').trim().replace(/\s+/g, ' ')
  const body = preview.length > 80 ? `${preview.slice(0, 77)}...` : (preview || 'New message in your HotPotChef chat.')
  const data = {
    meal_id: String(mealId ?? ''),
    message_id: String(message.id),
    alert_id: `msg-${message.id}`,
  }
  for (const userId of recipients) {
    await notifyUser(admin, userId, title, body, data)
  }
  return { sent: recipients.size, title }
}

