import { createClient, type SupabaseClient, type User } from 'https://esm.sh/@supabase/supabase-js@2'
import { jsonResponse } from './cors.ts'

export function bearerToken(req: Request): string {
  const header = req.headers.get('Authorization') ?? ''
  return header.replace(/^Bearer\s+/i, '').trim()
}

export function isServiceRoleRequest(req: Request): boolean {
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const token = bearerToken(req)
  return serviceKey.length > 0 && token.length > 0 && token === serviceKey
}

export function jsonUnauthorized(message = 'Unauthorized') {
  return jsonResponse({ success: false, error: message }, 401)
}

export async function requireUser(
  req: Request,
): Promise<{ user: User; userClient: SupabaseClient } | Response> {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return jsonUnauthorized()
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data, error } = await userClient.auth.getUser()
  if (error || !data.user) return jsonUnauthorized()
  return { user: data.user, userClient }
}

export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  )
}
