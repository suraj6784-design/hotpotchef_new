export function extractBearerToken(authorizationHeader) {
  if (!authorizationHeader) return null
  const match = authorizationHeader.match(/^Bearer\s+(\S+)/i)
  return match?.[1] ?? null
}

export function normalizeRole(role) {
  return (role ?? '').toString().trim().toLowerCase()
}

/**
 * Chef self-service only: the authenticated user must provision their own
 * payout account. Client-supplied chef_id is accepted only when it matches
 * auth.uid(). Non-chef roles are rejected when a role is present.
 */
export function authorizeChefAccount(input) {
  const userId = input.userId?.toString().trim() || null
  if (!userId) {
    return { ok: false, status: 401, error: 'Unauthorized' }
  }

  const requested = input.requestedChefId == null ? '' : String(input.requestedChefId).trim()
  if (requested && requested !== userId) {
    return { ok: false, status: 403, error: 'Forbidden' }
  }

  const role = normalizeRole(input.role)
  if (role && role !== 'chef') {
    return { ok: false, status: 403, error: 'Forbidden' }
  }

  return { ok: true, chefId: userId }
}
