import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { jsonResponse, optionsResponse } from '../_shared/cors.ts'
import { refundPayment } from '../_shared/razorpay.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') return optionsResponse()

  try {
    const cronSecret = Deno.env.get('OPS_CRON_SECRET') ?? ''
    const headerSecret = req.headers.get('x-ops-cron-secret') ?? ''
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const authHeader = req.headers.get('Authorization') ?? ''
    const asService = serviceKey.length > 0 && authHeader === `Bearer ${serviceKey}`
    const asCron = cronSecret.length > 0 && headerSecret === cronSecret
    if (!asService && !asCron) {
      return jsonResponse({ success: false, error: 'Unauthorized' }, 401)
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const admin = createClient(supabaseUrl, serviceKey)

    await admin.rpc('ops_escalate_overdue_tickets')
    try {
      await admin.rpc('expire_lapsed_fssai_licences')
    } catch (expireErr) {
      console.error('expire_lapsed_fssai_licences', expireErr)
    }

    const { data: rows, error } = await admin
      .from('orders')
      .select('id, payment_id, total_price, refund_status, refund_id')
      .eq('refund_status', 'failed')
      .not('payment_id', 'is', null)
      .order('updated_at', { ascending: true })
      .limit(25)
    if (error) throw new Error(error.message)

    let recovered = 0
    for (const row of rows ?? []) {
      const paymentId = String(row.payment_id ?? '')
      if (!paymentId) continue
      try {
        const refundPaise = Math.round(Number(row.total_price || 0) * 100)
        const refund = await refundPayment(paymentId, refundPaise > 0 ? refundPaise : undefined)
        await admin.from('orders').update({
          refund_id: refund?.id ?? row.refund_id,
          refund_status: refund?.status ?? 'processed',
          updated_at: new Date().toISOString(),
        }).eq('id', row.id)
        recovered += 1
      } catch {
        await admin.from('orders').update({
          refund_status: 'failed',
          updated_at: new Date().toISOString(),
        }).eq('id', row.id)
      }
    }

    return jsonResponse({
      success: true,
      failed_refunds_scanned: (rows ?? []).length,
      recovered,
    })
  } catch (err) {
    return jsonResponse({ success: false, error: (err as Error).message ?? 'Cron failed' }, 400)
  }
})
