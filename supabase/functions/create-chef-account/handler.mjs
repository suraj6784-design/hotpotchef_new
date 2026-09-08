import { authorizeChefAccount, extractBearerToken } from './authorize.mjs'

const jsonHeaders = { 'Content-Type': 'application/json' }

export function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders })
}

/**
 * @param {Request} req
 * @param {{
 *   getUser: (token: string) => Promise<{ id: string, user_metadata?: Record<string, unknown> } | null>,
 *   findCallerRow: (userId: string) => Promise<{ gateway_account_id?: string | null, role?: string | null } | null>,
 *   enablePayout: (chefId: string, accountId: string) => Promise<void>,
 *   now?: () => number,
 * }} deps
 */
export async function handleCreateChefAccount(req, deps) {
  const token = extractBearerToken(req.headers.get('Authorization'))
  if (!token) {
    return jsonResponse({ error: 'Unauthorized' }, 401)
  }

  const caller = await deps.getUser(token)
  if (!caller) {
    return jsonResponse({ error: 'Unauthorized' }, 401)
  }

  let body = {}
  try {
    body = await req.json()
  } catch {
    body = {}
  }

  const userData = await deps.findCallerRow(caller.id)
  const role = userData?.role ?? caller.user_metadata?.role
  const decision = authorizeChefAccount({
    userId: caller.id,
    requestedChefId: body.chef_id == null ? null : String(body.chef_id),
    role,
  })

  if (!decision.ok) {
    return jsonResponse({ error: decision.error }, decision.status)
  }

  if (userData?.gateway_account_id) {
    return jsonResponse({ success: true, account_id: userData.gateway_account_id })
  }

  const mockAccountId = `acc_mock_${(deps.now ?? Date.now)()}`
  await deps.enablePayout(decision.chefId, mockAccountId)
  return jsonResponse({ success: true, account_id: mockAccountId })
}
