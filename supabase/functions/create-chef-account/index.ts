// supabase/functions/create-chef-account/index.ts
// Auth model: chef self-service. JWT required; chef_id is derived from auth.uid().
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { handleCreateChefAccount, jsonResponse } from './handler.mjs'

serve(async (req) => {
  try {
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    return await handleCreateChefAccount(req, {
      async getUser(token) {
        const { data, error } = await supabaseAdmin.auth.getUser(token)
        if (error || !data.user) return null
        return data.user
      },
      async findCallerRow(userId) {
        const { data } = await supabaseAdmin
          .from('users')
          .select('gateway_account_id, role')
          .eq('id', userId)
          .maybeSingle()
        return data
      },
      async enablePayout(chefId, accountId) {
        await supabaseAdmin.from('users').update({
          gateway_account_id: accountId,
          payout_enabled: true,
        }).eq('id', chefId)
      },
    })
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Bad request'
    return jsonResponse({ error: message }, 400)
  }
})
