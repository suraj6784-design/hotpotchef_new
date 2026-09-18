import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { jsonResponse, optionsResponse } from '../_shared/cors.ts'
import { createRouteLinkedAccount } from '../_shared/razorpay.ts'
import { authorizeChefAccount } from './authorize.mjs'

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
    const admin = createClient(supabaseUrl, serviceKey)
    const { data: roleRow } = await admin
      .from('users')
      .select('role')
      .eq('id', userData.user.id)
      .maybeSingle()
    const authz = authorizeChefAccount({
      userId: userData.user.id,
      requestedChefId: body.chef_id,
      role: roleRow?.role
        ?? userData.user.app_metadata?.role
        ?? userData.user.user_metadata?.role,
    })
    if (!authz.ok) {
      return jsonResponse({ success: false, error: authz.error }, authz.status)
    }
    const chefId = authz.chefId
    const bankAccount = String(body.bank_account ?? '').replace(/\s+/g, '')
    const ifsc = String(body.ifsc_code ?? '').trim().toUpperCase()
    const beneficiary = String(body.beneficiary_name ?? '').trim()
    if (!bankAccount || !ifsc || !beneficiary) {
      return jsonResponse({ success: false, error: 'Beneficiary name, account number, and IFSC are required' }, 400)
    }

    const { data: existing } = await admin
      .from('users')
      .select('gateway_account_id, payout_enabled, email, phone, name, pan_number, gstin, address, city')
      .eq('id', chefId)
      .maybeSingle()

    const currentAccount = existing?.gateway_account_id?.toString() ?? ''
    const isLiveAccount = currentAccount.startsWith('acc_') && !currentAccount.startsWith('acc_mock_')

    const bankPatch = {
      bank_account_number: bankAccount,
      bank_ifsc: ifsc,
      beneficiary_name: beneficiary,
      updated_at: new Date().toISOString(),
    }

    if (isLiveAccount) {
      await admin.from('users').update({
        ...bankPatch,
        payout_enabled: true,
      }).eq('id', chefId)
      return jsonResponse({
        success: true,
        pending: false,
        payout_enabled: true,
        account_id: currentAccount,
      })
    }

    try {
      const linked = await createRouteLinkedAccount({
        chefId,
        email: String(body.email || existing?.email || userData.user.email || ''),
        phone: String(body.phone || existing?.phone || ''),
        name: String(body.name || existing?.name || beneficiary),
        bankAccount,
        ifsc,
        beneficiary,
        pan: String(existing?.pan_number || body.pan || '').toUpperCase(),
        gstin: String(existing?.gstin || body.gstin || ''),
        street: String(existing?.address || ''),
        city: String(existing?.city || 'Pune'),
      })
      await admin.from('users').update({
        ...bankPatch,
        gateway_account_id: linked.accountId,
        payout_enabled: true,
      }).eq('id', chefId)
      return jsonResponse({
        success: true,
        pending: false,
        payout_enabled: true,
        account_id: linked.accountId,
      })
    } catch (routeErr) {
      await admin.from('users').update({
        ...bankPatch,
        payout_enabled: false,
      }).eq('id', chefId)
      return jsonResponse({
        success: true,
        pending: true,
        payout_enabled: false,
        message: `Bank details saved. Razorpay Route is not active yet: ${routeErr?.message ?? routeErr}`,
      })
    }
  } catch (err) {
    return jsonResponse({ success: false, error: err?.message ?? String(err) }, 400)
  }
})
