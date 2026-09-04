import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { jsonResponse, optionsResponse } from '../_shared/cors.ts'
import { createPaymentTransfer } from '../_shared/razorpay.ts'
import {
  chefPayoutBreakdown,
  DEFAULT_PLATFORM_MARGIN_RATE,
  itemsTotalFromLines,
  parseOrderItems,
} from '../_shared/payout.ts'

function asNumber(value: unknown, fallback = 0) {
  const n = Number(value)
  return Number.isFinite(n) ? n : fallback
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return optionsResponse()

  try {
    const body = await req.json().catch(() => ({}))
    const record = body.record && typeof body.record === 'object' ? body.record : null
    const orderId = String(body.order_id ?? record?.id ?? '')
    if (!orderId) return jsonResponse({ success: false, error: 'order_id is required' }, 400)

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const admin = createClient(supabaseUrl, serviceKey)

    const { data: order, error: orderError } = await admin
      .from('orders')
      .select('*')
      .eq('id', orderId)
      .maybeSingle()
    if (orderError) throw new Error(orderError.message)
    if (!order) return jsonResponse({ success: false, error: 'Order not found' }, 404)

    const status = String(order.status ?? '').toLowerCase()
    if (status.includes('cancel') || status.includes('reject')) {
      await admin.from('orders').update({
        payout_status: 'not_applicable',
        chef_payout: 0,
        platform_margin: 0,
        updated_at: new Date().toISOString(),
      }).eq('id', orderId)
      return jsonResponse({ success: true, skipped: true, reason: 'cancelled' })
    }
    if (!status.includes('deliver') && !status.includes('complet')) {
      return jsonResponse({ success: true, skipped: true, reason: 'not_delivered' })
    }

    const payoutStatus = String(order.payout_status ?? 'pending').toLowerCase()
    if (['released', 'paid', 'transferred', 'not_applicable'].includes(payoutStatus)) {
      return jsonResponse({ success: true, skipped: true, reason: 'already_handled', payout_status: payoutStatus })
    }
    if (order.razorpay_transfer_id) {
      return jsonResponse({ success: true, skipped: true, reason: 'transfer_exists', transfer_id: order.razorpay_transfer_id })
    }

    const items = parseOrderItems(order.items ?? order.cart_items)
    const itemsTotal = itemsTotalFromLines(items)
    const packagingFee = asNumber(order.packaging_fee, 20)
    const marginRate = asNumber(Deno.env.get('PLATFORM_MARGIN_RATE'), DEFAULT_PLATFORM_MARGIN_RATE)
    const payout = chefPayoutBreakdown(itemsTotal, packagingFee, marginRate)
    const amountPaise = Math.round(payout.chefPayout * 100)

    const claimed = await admin.from('orders').update({
      payout_status: 'processing',
      chef_payout: payout.chefPayout,
      platform_margin: payout.margin,
      updated_at: new Date().toISOString(),
    }).eq('id', orderId).or('payout_status.is.null,payout_status.eq.pending,payout_status.eq.failed').select('id')

    if (!claimed.data || claimed.data.length === 0) {
      return jsonResponse({ success: true, skipped: true, reason: 'already_processing' })
    }

    if (amountPaise < 100) {
      await admin.from('orders').update({
        payout_status: 'released',
        chef_payout: 0,
        platform_margin: payout.margin,
        payout_released_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }).eq('id', orderId)
      return jsonResponse({ success: true, skipped: true, reason: 'payout_too_small' })
    }

    const { data: chef } = await admin
      .from('users')
      .select('gateway_account_id')
      .eq('id', order.chef_id)
      .maybeSingle()
    const accountId = chef?.gateway_account_id?.toString() ?? ''
    if (!accountId) {
      await admin.from('orders').update({
        payout_status: 'awaiting_account',
        chef_payout: payout.chefPayout,
        platform_margin: payout.margin,
        updated_at: new Date().toISOString(),
      }).eq('id', orderId)
      return jsonResponse({
        success: true,
        recorded: true,
        reason: 'missing_gateway_account',
        chef_payout: payout.chefPayout,
      })
    }

    const paymentId = order.payment_id?.toString() ?? ''
    if (!paymentId) {
      await admin.from('orders').update({
        payout_status: 'recorded',
        chef_payout: payout.chefPayout,
        platform_margin: payout.margin,
        updated_at: new Date().toISOString(),
      }).eq('id', orderId)
      return jsonResponse({
        success: true,
        recorded: true,
        reason: 'missing_payment_id',
        chef_payout: payout.chefPayout,
      })
    }

    try {
      const transfer = await createPaymentTransfer(paymentId, accountId, amountPaise, {
        order_id: orderId,
        chef_id: String(order.chef_id ?? ''),
      })
      await admin.from('orders').update({
        payout_status: 'released',
        chef_payout: payout.chefPayout,
        platform_margin: payout.margin,
        razorpay_transfer_id: transfer?.id ?? null,
        payout_released_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }).eq('id', orderId)
      return jsonResponse({
        success: true,
        transfer_id: transfer?.id ?? null,
        chef_payout: payout.chefPayout,
        platform_margin: payout.margin,
      })
    } catch (transferErr) {
      await admin.from('orders').update({
        payout_status: 'failed',
        chef_payout: payout.chefPayout,
        platform_margin: payout.margin,
        updated_at: new Date().toISOString(),
      }).eq('id', orderId)
      throw transferErr
    }
  } catch (err) {
    return jsonResponse({ success: false, error: err.message ?? 'Chef payout failed' }, 400)
  }
})
