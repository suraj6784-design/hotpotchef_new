// FCM HTTP v1 access token without npm:google-auth-library.
// That package is a documented Edge BOOT_ERROR on this project.
// Do not name a binding `auth` here or in send-push-notification (SyntaxError if
// paired with authorizeInternalInvoke's historical `const auth`).

type ServiceAccount = {
  client_email?: string
  private_key?: string
  project_id?: string
}

type TokenCache = { token: string; exp: number }

let cached: TokenCache | null = null

function base64Url(data: Uint8Array | string): string {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : data
  let bin = ''
  for (const byte of bytes) bin += String.fromCharCode(byte)
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '')
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const b64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '')
  const raw = atob(b64)
  const buf = new Uint8Array(raw.length)
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i)
  return buf.buffer
}

async function googleAccessToken(account: ServiceAccount): Promise<string | null> {
  const email = account.client_email?.trim() ?? ''
  const pem = (account.private_key ?? '').replace(/\\n/g, '\n')
  if (!email || !pem.includes('BEGIN PRIVATE KEY')) return null

  const now = Math.floor(Date.now() / 1000)
  if (cached && cached.exp - 60 > now) return cached.token

  const header = base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const claim = base64Url(JSON.stringify({
    iss: email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }))
  const unsigned = `${header}.${claim}`
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToPkcs8(pem),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  )
  const jwt = `${unsigned}.${base64Url(new Uint8Array(sig))}`
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  })
  const body = await res.json() as { access_token?: string; expires_in?: number }
  const token = body.access_token?.trim() ?? ''
  if (!token) return null
  cached = { token, exp: now + Math.max(60, Number(body.expires_in) || 3600) }
  return token
}

export async function sendFcm(
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
) {
  const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}'
  let account: ServiceAccount = {}
  try {
    account = JSON.parse(raw) as ServiceAccount
  } catch {
    return
  }
  const projectId = account.project_id?.trim() ?? ''
  if (!projectId || !token) return

  const accessToken = await googleAccessToken(account)
  if (!accessToken) return

  await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        data,
        android: {
          collapseKey: data.alert_id || 'hotpotchef',
          notification: { tag: data.alert_id || 'hotpotchef' },
        },
        apns: {
          headers: { 'apns-collapse-id': data.alert_id || 'hotpotchef' },
        },
      },
    }),
  })
}
