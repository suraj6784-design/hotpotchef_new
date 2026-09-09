import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { jsonResponse, optionsResponse } from '../_shared/cors.ts'

const HELPER_DOMAIN = 'helpers.hotpotchef.app'
const ALLOWED = ['dashboard', 'packaging', 'fssai', 'brands', 'refunds', 'tickets', 'kyc']

function jsonFail(message: string, status = 400) {
  return jsonResponse({ ok: false, error: message }, status)
}

function normalizeLogin(raw: string) {
  const value = String(raw ?? '').trim().toLowerCase()
  if (!value) return ''
  if (value.includes('@')) return value
  const user = value.replace(/[^a-z0-9._-]/g, '')
  if (user.length < 3) return ''
  return `${user}@${HELPER_DOMAIN}`
}

function normalizePerms(raw: unknown) {
  const out: string[] = []
  const list = Array.isArray(raw) ? raw : []
  for (const item of list) {
    const key = String(item ?? '').trim().toLowerCase()
    if (ALLOWED.includes(key) && !out.includes(key)) out.push(key)
  }
  return out
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return optionsResponse()

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return jsonFail('Unauthorized', 401)

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: userData, error: userError } = await userClient.auth.getUser()
    if (userError || !userData.user) return jsonFail('Unauthorized', 401)

    const { data: isOwner, error: ownerErr } = await userClient.rpc('is_platform_owner')
    if (ownerErr || isOwner !== true) return jsonFail('Platform owner only', 403)

    const body = await req.json().catch(() => ({}))
    const action = String(body.action ?? 'create').trim().toLowerCase()
    const admin = createClient(supabaseUrl, serviceKey)

    if (action === 'create') {
      const email = normalizeLogin(String(body.username ?? body.email ?? ''))
      const password = String(body.password ?? '')
      const label = String(body.label ?? body.name ?? '').trim()
      const perms = normalizePerms(body.permissions)
      if (!email.includes('@')) return jsonFail('Enter a username (3+ letters) or email')
      if (password.length < 8) return jsonFail('Password must be at least 8 characters')
      if (perms.length === 0) return jsonFail('Select at least one permission')
      if (email === String(userData.user.email ?? '').toLowerCase()) {
        return jsonFail('Cannot create a helper on the owner login')
      }

      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          name: label || email.split('@')[0],
          role: 'Admin',
          helper: true,
        },
      })
      if (createErr || !created.user) {
        const msg = createErr?.message ?? 'Could not create login'
        if (msg.toLowerCase().includes('already')) {
          return jsonFail('That username or email is already in use')
        }
        return jsonFail(msg)
      }

      const userId = created.user.id
      const name = label || email.split('@')[0]
      await admin.from('users').upsert({
        id: userId,
        email,
        name,
        full_name: name,
        role: 'Admin',
        account_status: 'active',
      }, { onConflict: 'id' })
      await admin.from('platform_ops').upsert({
        user_id: userId,
        seat_role: 'helper',
        permissions: perms,
        note: name,
        created_by: userData.user.id,
        revoked_at: null,
      }, { onConflict: 'user_id' })
      return jsonResponse({
        ok: true,
        user_id: userId,
        email,
        username: email.endsWith(`@${HELPER_DOMAIN}`) ? email.split('@')[0] : email,
        permissions: perms,
      })
    }

    const userId = String(body.user_id ?? '').trim()
    if (!userId) return jsonFail('Helper id required')

    const { data: seat } = await admin
      .from('platform_ops')
      .select('user_id, seat_role')
      .eq('user_id', userId)
      .maybeSingle()
    if (!seat || seat.seat_role !== 'helper') return jsonFail('Helper seat not found')

    if (action === 'revoke') {
      await admin.from('platform_ops').update({ revoked_at: new Date().toISOString() }).eq('user_id', userId)
      await admin.from('users').update({ role: 'Customer' }).eq('id', userId)
      await admin.auth.admin.updateUserById(userId, { user_metadata: { role: 'Customer', helper: false } })
      return jsonResponse({ ok: true, action })
    }

    if (action === 'restore') {
      const perms = normalizePerms(body.permissions)
      await admin.from('platform_ops').update({
        revoked_at: null,
        ...(perms.length > 0 ? { permissions: perms } : {}),
      }).eq('user_id', userId)
      await admin.from('users').update({ role: 'Admin', account_status: 'active' }).eq('id', userId)
      await admin.auth.admin.updateUserById(userId, { user_metadata: { role: 'Admin', helper: true } })
      return jsonResponse({ ok: true, action })
    }

    if (action === 'suspend') {
      await admin.from('users').update({ account_status: 'suspended' }).eq('id', userId)
      return jsonResponse({ ok: true, action })
    }

    if (action === 'unsuspend') {
      await admin.from('users').update({ account_status: 'active' }).eq('id', userId)
      return jsonResponse({ ok: true, action })
    }

    if (action === 'delete') {
      const { error: delErr } = await admin.auth.admin.deleteUser(userId)
      if (delErr) {
        await admin.from('platform_ops').update({ revoked_at: new Date().toISOString() }).eq('user_id', userId)
        await admin.from('users').update({ account_status: 'suspended', role: 'Customer' }).eq('id', userId)
        return jsonFail(delErr.message)
      }
      return jsonResponse({ ok: true, action })
    }

    return jsonFail('Unknown action')
  } catch (err) {
    return jsonFail(err?.message ?? String(err), 400)
  }
})
