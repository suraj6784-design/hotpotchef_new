import {
  RAZORPAY_API_BASE,
  basicAuthHeader,
  payoutModeForKeys,
  razorpayErrorMessage,
} from '../_shared/razorpay_route.mjs'

function trim(value) {
  return String(value ?? '').trim()
}

function digits(value) {
  return String(value ?? '').replace(/\D/g, '')
}

export function validateChefBankDetails(body) {
  const email = trim(body?.email)
  const bank = digits(body?.bank_account)
  const ifsc = trim(body?.ifsc_code).toUpperCase()
  const beneficiary = trim(body?.beneficiary_name || body?.name)
  if (!email) return 'Email is required to create a Razorpay Route account'
  if (bank.length < 5 || bank.length > 35) return 'Bank account number is required'
  if (!/^[A-Z]{4}0[A-Z0-9]{6}$/.test(ifsc)) return 'A valid IFSC code is required'
  if (!beneficiary) return 'Beneficiary name is required'
  return null
}

function legalBusinessName(input) {
  const name = trim(input?.name || input?.beneficiary_name || 'Home Chef')
  if (name.length >= 4) return name.slice(0, 200)
  return `${name} Kitchen`.slice(0, 200)
}

/**
 * Official Route Linked Account create body (POST /v2/accounts).
 * Bank details are attached later via the Route product configuration.
 */
export function buildV2LinkedAccountPayload(input) {
  const name = legalBusinessName(input)
  const phone = digits(input?.phone).slice(-15)
  const street1 = trim(input?.street || input?.house || 'Home kitchen') || 'Home kitchen'
  const city = trim(input?.city) || 'Mumbai'
  const state = trim(input?.state) || 'MAHARASHTRA'
  const postal = digits(input?.postal_code || input?.pincode).slice(0, 10) || '400001'

  return {
    email: trim(input?.email),
    phone: phone || undefined,
    type: 'route',
    legal_business_name: name,
    customer_facing_business_name: name,
    business_type: 'individual',
    contact_name: trim(input?.beneficiary_name || input?.name || name),
    reference_id: trim(input?.chef_id).slice(0, 40) || undefined,
    profile: {
      category: 'food',
      subcategory: 'online_food_ordering',
      addresses: {
        registered: {
          street1: street1.slice(0, 100),
          street2: trim(input?.house),
          city,
          state,
          postal_code: postal,
          country: 'IN',
        },
      },
    },
  }
}

export function buildV2ProductRequestPayload() {
  return { product_name: 'route', tnc_accepted: true }
}

export function buildV2SettlementsPayload(input) {
  return {
    settlements: {
      account_number: digits(input?.bank_account),
      ifsc_code: trim(input?.ifsc_code).toUpperCase(),
      beneficiary_name: trim(input?.beneficiary_name || input?.name),
    },
  }
}

/**
 * Classic Route linked-account body (POST /v1/beta/accounts).
 * Used when Accounts v2 is not enabled on the Razorpay Test-mode merchant.
 */
export function buildV1BetaLinkedAccountPayload(input) {
  const name = legalBusinessName(input)
  return {
    name,
    email: trim(input?.email),
    tnc_accepted: true,
    account_details: {
      business_name: name,
      business_type: 'individual',
    },
    bank_account: {
      ifsc_code: trim(input?.ifsc_code).toUpperCase(),
      beneficiary_name: trim(input?.beneficiary_name || input?.name || name),
      account_number: digits(input?.bank_account),
    },
  }
}

export function isV2RouteUnavailable(status, data) {
  if (status === 404) return true
  const desc = String(data?.error?.description || data?.error?.code || '').toLowerCase()
  return desc.includes('not found on the server') ||
    desc.includes('marketplace feature is not enabled')
}

async function razorpayJson(fetchImpl, { keyId, keySecret, method, path, body }) {
  const response = await fetchImpl(`${RAZORPAY_API_BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      Authorization: basicAuthHeader(keyId, keySecret),
    },
    body: body == null ? undefined : JSON.stringify(body),
  })
  const data = await response.json().catch(() => ({}))
  return { ok: response.ok, status: response.status, data }
}

/**
 * Create a Razorpay Route linked account using Test (or Live) API keys.
 * Never invents acc_mock_* — callers must take the mock path before this.
 */
export async function createRouteLinkedAccount(input, { keyId, keySecret, fetchImpl } = {}) {
  if (!keyId || !keySecret) {
    throw new Error('Razorpay keys missing')
  }
  const fetchFn = fetchImpl ?? globalThis.fetch
  if (typeof fetchFn !== 'function') {
    throw new Error('Fetch implementation missing')
  }

  const v2Account = await razorpayJson(fetchFn, {
    keyId,
    keySecret,
    method: 'POST',
    path: '/v2/accounts',
    body: buildV2LinkedAccountPayload(input),
  })

  if (v2Account.ok && v2Account.data?.id) {
    const accountId = String(v2Account.data.id)
    const product = await razorpayJson(fetchFn, {
      keyId,
      keySecret,
      method: 'POST',
      path: `/v2/accounts/${accountId}/products`,
      body: buildV2ProductRequestPayload(),
    })

    let settlementsAttached = false
    if (product.ok && product.data?.id) {
      const productId = String(product.data.id)
      const settlements = await razorpayJson(fetchFn, {
        keyId,
        keySecret,
        method: 'PATCH',
        path: `/v2/accounts/${accountId}/products/${productId}`,
        body: buildV2SettlementsPayload(input),
      })
      settlementsAttached = settlements.ok
      if (!settlements.ok) {
        const error = new Error(
          razorpayErrorMessage(settlements.data, 'Failed to attach settlement bank details'),
        )
        error.accountId = accountId
        error.status = settlements.status
        throw error
      }
    }

    return {
      accountId,
      mock: false,
      mode: payoutModeForKeys(keyId),
      api: 'v2',
      settlementsAttached,
    }
  }

  if (isV2RouteUnavailable(v2Account.status, v2Account.data)) {
    const v1 = await razorpayJson(fetchFn, {
      keyId,
      keySecret,
      method: 'POST',
      path: '/v1/beta/accounts',
      body: buildV1BetaLinkedAccountPayload(input),
    })
    if (v1.ok && v1.data?.id) {
      return {
        accountId: String(v1.data.id),
        mock: false,
        mode: payoutModeForKeys(keyId),
        api: 'v1_beta',
        settlementsAttached: true,
      }
    }
    throw new Error(
      razorpayErrorMessage(v1.data, razorpayErrorMessage(v2Account.data, 'Razorpay linked account creation failed')),
    )
  }

  throw new Error(razorpayErrorMessage(v2Account.data, 'Razorpay linked account creation failed'))
}
