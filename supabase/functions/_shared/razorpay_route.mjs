// Shared Razorpay Route helpers for edge functions.
// Test vs live is selected by the key prefix (rzp_test_ / rzp_live_), not by code paths.

export const RAZORPAY_API_BASE = 'https://api.razorpay.com'

export function readRazorpayKeys(envGet) {
  const get = envGet ?? ((key) => {
    try {
      return globalThis.Deno?.env?.get(key) ?? ''
    } catch {
      return ''
    }
  })
  return {
    keyId: String(get('RAZORPAY_KEY_ID') ?? '').trim(),
    keySecret: String(get('RAZORPAY_KEY_SECRET') ?? '').trim(),
  }
}

export function hasRazorpayKeys(keys) {
  return Boolean(keys?.keyId && keys?.keySecret)
}

export function razorpayKeyMode(keyId) {
  const id = String(keyId ?? '')
  if (id.startsWith('rzp_test_')) return 'test'
  if (id.startsWith('rzp_live_')) return 'live'
  return 'unknown'
}

export function payoutModeForKeys(keyId) {
  const mode = razorpayKeyMode(keyId)
  return mode === 'live' ? 'live' : 'test'
}

export function isMockAccountId(accountId) {
  return String(accountId ?? '').startsWith('acc_mock_')
}

export function isRealRouteAccountId(accountId) {
  const id = String(accountId ?? '').trim()
  return id.startsWith('acc_') && !isMockAccountId(id)
}

export function classifyGatewayAccount(accountId, options = {}) {
  const id = String(accountId ?? '').trim()
  if (options.mockFlag === true || isMockAccountId(id)) {
    return { kind: 'mock', mock: true, mode: 'mock' }
  }
  if (!id) {
    return { kind: 'missing', mock: false, mode: 'missing' }
  }
  const mode = payoutModeForKeys(options.keyId)
  return { kind: mode, mock: false, mode }
}

export function basicAuthHeader(keyId, keySecret) {
  return `Basic ${btoa(`${keyId}:${keySecret}`)}`
}

export function isSkippedTransferStatus(status) {
  return String(status ?? '').startsWith('skipped_')
}

export function razorpayErrorMessage(data, fallback) {
  return data?.error?.description || data?.error?.reason || fallback
}
