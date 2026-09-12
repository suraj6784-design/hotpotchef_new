import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { handleCreateChefAccount } from './handler.mjs'

const chefId = '11111111-1111-1111-1111-111111111111'
const otherChefId = '22222222-2222-2222-2222-222222222222'

function post(body, headers = {}) {
  return new Request('http://localhost/create-chef-account', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  })
}

async function read(response) {
  return { status: response.status, body: await response.json() }
}

function chefDeps(overrides = {}) {
  return {
    async getUser(token) {
      if (token !== 'valid-chef-jwt') return null
      return { id: chefId, user_metadata: { role: 'Chef' } }
    },
    async findCallerRow() {
      return { gateway_account_id: null, role: 'Chef' }
    },
    async enablePayout() {},
    now: () => 1700000000000,
    ...overrides,
  }
}

describe('handleCreateChefAccount', () => {
  it('rejects unauthenticated invokes with 401', async () => {
    const missing = await read(await handleCreateChefAccount(
      post({ chef_id: chefId }),
      chefDeps(),
    ))
    assert.equal(missing.status, 401)
    assert.deepEqual(missing.body, { error: 'Unauthorized' })

    const invalid = await read(await handleCreateChefAccount(
      post({ chef_id: chefId }, { Authorization: 'Bearer expired-or-anon' }),
      chefDeps(),
    ))
    assert.equal(invalid.status, 401)
    assert.deepEqual(invalid.body, { error: 'Unauthorized' })
  })

  it('rejects chef_id spoofing with 403', async () => {
    const result = await read(await handleCreateChefAccount(
      post({ chef_id: otherChefId, email: 'chef@example.com' }, { Authorization: 'Bearer valid-chef-jwt' }),
      chefDeps(),
    ))
    assert.equal(result.status, 403)
    assert.deepEqual(result.body, { error: 'Forbidden' })
  })

  it('rejects a signed-in customer enabling payouts', async () => {
    const result = await read(await handleCreateChefAccount(
      post({ chef_id: chefId }, { Authorization: 'Bearer valid-chef-jwt' }),
      chefDeps({
        async findCallerRow() {
          return { gateway_account_id: null, role: 'Customer' }
        },
      }),
    ))
    assert.equal(result.status, 403)
    assert.deepEqual(result.body, { error: 'Forbidden' })
  })

  it('provisions a mock account for the authenticated chef (Flutter call site)', async () => {
    const updates = []
    const result = await read(await handleCreateChefAccount(
      post({
        chef_id: chefId,
        email: 'chef@example.com',
        name: 'Test Kitchen',
        phone: '9999999999',
      }, { Authorization: 'Bearer valid-chef-jwt' }),
      chefDeps({
        async enablePayout(id, accountId) {
          updates.push({ id, accountId })
        },
      }),
    ))

    assert.equal(result.status, 200)
    assert.deepEqual(result.body, { success: true, account_id: 'acc_mock_1700000000000', mock: true })
    assert.deepEqual(updates, [{ id: chefId, accountId: 'acc_mock_1700000000000' }])
  })

  it('returns an existing gateway account without writing again', async () => {
    let wrote = false
    const result = await read(await handleCreateChefAccount(
      post({ chef_id: chefId }, { Authorization: 'Bearer valid-chef-jwt' }),
      chefDeps({
        async findCallerRow() {
          return { gateway_account_id: 'acc_existing', role: 'Chef' }
        },
        async enablePayout() {
          wrote = true
        },
      }),
    ))

    assert.equal(result.status, 200)
    assert.deepEqual(result.body, { success: true, account_id: 'acc_existing', mock: false })
    assert.equal(wrote, false)
  })

  it('derives chef_id from the JWT when the body omits it', async () => {
    const updates = []
    const result = await read(await handleCreateChefAccount(
      post({ email: 'chef@example.com' }, { Authorization: 'Bearer valid-chef-jwt' }),
      chefDeps({
        async enablePayout(id, accountId) {
          updates.push({ id, accountId })
        },
      }),
    ))

    assert.equal(result.status, 200)
    assert.equal(updates[0].id, chefId)
    assert.equal(result.body.success, true)
  })
})
