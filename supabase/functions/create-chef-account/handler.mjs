import { authorizeChefAccount, extractBearerToken } from './authorize.mjs'
import { createRouteLinkedAccount, validateChefBankDetails } from './razorpay_accounts.mjs'
import {
  classifyGatewayAccount,
  hasRazorpayKeys,
  readRazorpayKeys,
} from '../_shared/razorpay_route.mjs'

const jsonHeaders = { 'Content-Type': 'application/json' }

export function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders })
}

function defaultGetRazorpayKeys() {
  return readRazorpayKeys()
}

/**
 * @param {Request} req
 * @param {{
 *   getUser: (token: string) => Promise<{ id: string, user_metadata?: Record<string, unknown> } | null>,
 *   findCallerRow: (userId: string) => Promise<{ gateway_account_id?: string | null, role?: string | null } | null>,
 *   enablePayout: (chefId: string, accountId: string) => Promise<void>,
 *   getRazorpayKeys?: () => { keyId: string, keySecret: string },
 *   createLinkedAccount?: (input: Record<string, unknown>, keys: { keyId: string, keySecret: string }) => Promise<{ accountId: string, mock: boolean, mode: string, api?: string, settlementsAttached?: boolean }>,
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

  const keys = (deps.getRazorpayKeys ?? defaultGetRazorpayKeys)()

  if (userData?.gateway_account_id) {
    const existing = String(userData.gateway_account_id)
    const classified = classifyGatewayAccount(existing, { keyId: keys.keyId })
    return jsonResponse({
      success: true,
      account_id: existing,
      mock: classified.mock,
      mode: classified.mode,
    })
  }

  // Mock / local-dev fallback only when Test (or Live) keys are absent.
  if (!hasRazorpayKeys(keys)) {
    const mockAccountId = `acc_mock_${(deps.now ?? Date.now)()}`
    await deps.enablePayout(decision.chefId, mockAccountId)
    return jsonResponse({
      success: true,
      account_id: mockAccountId,
      mock: true,
      mode: 'mock',
    })
  }

  const invalid = validateChefBankDetails(body)
  if (invalid) {
    return jsonResponse({ error: invalid }, 400)
  }

  const createLinkedAccount = deps.createLinkedAccount ?? createRouteLinkedAccount
  try {
    const created = await createLinkedAccount(
      { ...body, chef_id: decision.chefId },
      { keyId: keys.keyId, keySecret: keys.keySecret },
    )
    await deps.enablePayout(decision.chefId, created.accountId)
    return jsonResponse({
      success: true,
      account_id: created.accountId,
      mock: false,
      mode: created.mode,
      api: created.api ?? null,
      settlements_attached: created.settlementsAttached !== false,
    })
  } catch (err) {
    if (err?.accountId) {
      await deps.enablePayout(decision.chefId, err.accountId)
    }
    const message = err instanceof Error ? err.message : 'Razorpay linked account creation failed'
    return jsonResponse({
      error: message,
      account_id: err?.accountId ?? null,
    }, 400)
  }
}
