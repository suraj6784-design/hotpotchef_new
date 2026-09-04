import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { jsonResponse, optionsResponse } from '../_shared/cors.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') return optionsResponse()

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return jsonResponse({ success: false, error: 'Unauthorized' }, 401)

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: userData, error: userError } = await userClient.auth.getUser()
    if (userError || !userData.user) {
      return jsonResponse({ success: false, error: 'Unauthorized' }, 401)
    }

    const body = await req.json().catch(() => ({}))
    const chefId = String(body.chef_id ?? userData.user.id)
    if (chefId !== userData.user.id) {
      return jsonResponse({ success: false, error: 'You can only link your own payout account' }, 403)
    }

    const admin = createClient(supabaseUrl, serviceKey)
    const bankAccount = String(body.bank_account ?? '').replace(/\s+/g, '')
    const ifsc = String(body.ifsc_code ?? '').trim().toUpperCase()
    const beneficiary = String(body.beneficiary_name ?? '').trim()

    const { data: existing } = await admin
      .from('users')
      .select('gateway_account_id, payout_enabled')
      .eq('id', chefId)
      .maybeSingle()

    const currentAccount = existing?.gateway_account_id?.toString() ?? ''
    const isLiveAccount = currentAccount.startsWith('acc_') && !currentAccount.startsWith('acc_mock_')

    await admin.from('users').update({
      bank_account_number: bankAccount || null,
      bank_ifsc: ifsc || null,
      beneficiary_name: beneficiary || null,
      payout_enabled: isLiveAccount,
      updated_at: new Date().toISOString(),
    }).eq('id', chefId)

    if (isLiveAccount) {
      return jsonResponse({
        success: true,
        pending: false,
        payout_enabled: true,
        account_id: currentAccount,
      })
    }

    return jsonResponse({
      success: true,
      pending: true,
      payout_enabled: false,
      message: 'Bank details saved. Enable Razorpay Route, then chefs can receive automatic settlements.',
    })
  } catch (err) {
    return jsonResponse({ success: false, error: err?.message ?? String(err) }, 400)
  }
})
