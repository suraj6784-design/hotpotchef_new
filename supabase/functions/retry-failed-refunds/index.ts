import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { jsonResponse, optionsResponse } from '../_shared/cors.ts'
import { refundPayment } from '../_shared/razorpay.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') return optionsResponse()

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const authHeader = req.headers.get('Authorization') ?? ''
    if (!serviceKey || authHeader !== `Bearer ${serviceKey}`) {
      return jsonResponse({ success: false, error: 'Unauthorized' }, 401)
    }

    const admin = createClient(supabaseUrl, serviceKey)
    const { data: rows, error } = await admin
      .from('orders')
      .select('id, payment_id, total_price, refund_status, refund_id')
      .eq('refund_status', 'failed')
      .not('payment_id', 'is', null)
      .order('updated_at', { ascending: true })
      .limit(25)

    if (error) throw new Error(error.message)

    let retried = 0
    let recovered = 0
    const failures: Array<{ id: string; error: string }> = []

    for (const row of rows ?? []) {
      const paymentId = String(row.payment_id ?? '')
      if (!paymentId) continue
      retried += 1
      try {
        const refundPaise = Math.round(Number(row.total_price || 0) * 100)
        const refund = await refundPayment(paymentId, refundPaise > 0 ? refundPaise : undefined)
        await admin.from('orders').update({
          refund_id: refund?.id ?? row.refund_id,
          refund_status: refund?.status ?? 'processed',
          updated_at: new Date().toISOString(),
        }).eq('id', row.id)
        recovered += 1
      } catch (e) {
        failures.push({ id: String(row.id), error: (e as Error).message ?? 'refund failed' })
        await admin.from('orders').update({
          refund_status: 'failed',
          updated_at: new Date().toISOString(),
        }).eq('id', row.id)
      }
    }

    return jsonResponse({
      success: true,
      scanned: (rows ?? []).length,
      retried,
      recovered,
      failures,
    })
  } catch (err) {
    return jsonResponse({ success: false, error: (err as Error).message ?? 'Retry failed' }, 400)
  }
})
