import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { authorizeChefAccount, extractBearerToken } from './authorize.mjs'

const chefId = '11111111-1111-1111-1111-111111111111'
const otherChefId = '22222222-2222-2222-2222-222222222222'

describe('extractBearerToken', () => {
  it('rejects missing or non-bearer headers', () => {
    assert.equal(extractBearerToken(null), null)
    assert.equal(extractBearerToken(''), null)
    assert.equal(extractBearerToken('Basic abc'), null)
  })

  it('extracts a bearer token', () => {
    assert.equal(extractBearerToken('Bearer jwt-token'), 'jwt-token')
    assert.equal(extractBearerToken('bearer jwt-token'), 'jwt-token')
  })
})

describe('authorizeChefAccount', () => {
  it('returns 401 when the caller is unauthenticated', () => {
    assert.deepEqual(
      authorizeChefAccount({ userId: null, requestedChefId: chefId, role: 'Chef' }),
      { ok: false, status: 401, error: 'Unauthorized' },
    )
    assert.deepEqual(
      authorizeChefAccount({ userId: '  ', requestedChefId: chefId }),
      { ok: false, status: 401, error: 'Unauthorized' },
    )
  })

  it('returns 403 when chef_id is spoofed', () => {
    assert.deepEqual(
      authorizeChefAccount({ userId: chefId, requestedChefId: otherChefId, role: 'Chef' }),
      { ok: false, status: 403, error: 'Forbidden' },
    )
  })

  it('returns 403 for customer or driver roles on their own id', () => {
    assert.deepEqual(
      authorizeChefAccount({ userId: chefId, requestedChefId: chefId, role: 'Customer' }),
      { ok: false, status: 403, error: 'Forbidden' },
    )
    assert.deepEqual(
      authorizeChefAccount({ userId: chefId, requestedChefId: chefId, role: 'Driver' }),
      { ok: false, status: 403, error: 'Forbidden' },
    )
  })

  it('allows the Flutter chef call site (matching uid + Chef role)', () => {
    assert.deepEqual(
      authorizeChefAccount({ userId: chefId, requestedChefId: chefId, role: 'Chef' }),
      { ok: true, chefId },
    )
  })

  it('derives chef_id from the authenticated user when the body omits it', () => {
    assert.deepEqual(
      authorizeChefAccount({ userId: chefId, requestedChefId: null, role: 'chef' }),
      { ok: true, chefId },
    )
    assert.deepEqual(
      authorizeChefAccount({ userId: chefId, requestedChefId: '', role: 'chef' }),
      { ok: true, chefId },
    )
  })

  it('allows own-account setup when role is not yet stored', () => {
    assert.deepEqual(
      authorizeChefAccount({ userId: chefId, requestedChefId: chefId, role: null }),
      { ok: true, chefId },
    )
  })
})
