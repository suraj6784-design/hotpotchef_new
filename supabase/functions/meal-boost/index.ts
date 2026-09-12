import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { jsonResponse, optionsResponse } from '../_shared/cors.ts'
import { createRazorpayOrder, fetchPayment, verifyCheckoutSignature } from '../_shared/razorpay.ts'

const BOOST_PAISE = 9900

function boostEndsAtIso(now = new Date()) {
  const istMs = now.getTime() + 5.5 * 60 * 60 * 1000
  const ist = new Date(istMs)
  const nextMidnightUtc =
    Date.UTC(ist.getUTCFullYear(), ist.getUTCMonth(), ist.getUTCDate() + 1, 0, 0, 0) -
    5.5 * 60 * 60 * 1000
  return new Date(nextMidnightUtc).toISOString()
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return optionsResponse()

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return jsonResponse({ success: false, error: 'Unauthorized' }, 401)

    const body = await req.json().catch(() => ({}))
    const action = String(body.action ?? 'create').toLowerCase()

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: userData, error: userError } = await userClient.auth.getUser()
    if (userError || !userData.user) {
      return jsonResponse({ success: false, error: 'Unauthorized' }, 401)
    }
    const user = userData.user
    const admin = createClient(supabaseUrl, serviceKey)

    if (action === 'confirm') {
      const boostId = String(body.boost_id ?? '')
      const orderId = String(body.razorpay_order_id ?? '')
      const paymentId = String(body.razorpay_payment_id ?? '')
      const signature = String(body.razorpay_signature ?? '')
      if (!boostId || !orderId || !paymentId || !signature) {
        return jsonResponse({ success: false, error: 'Missing payment details' }, 400)
      }
      const ok = await verifyCheckoutSignature(orderId, paymentId, signature)
      if (!ok) return jsonResponse({ success: false, error: 'Payment signature did not match' }, 400)
      const payment = await fetchPayment(paymentId)
      if (payment.status !== 'captured' && payment.status !== 'authorized') {
        return jsonResponse({ success: false, error: `Payment is ${payment.status}` }, 400)
      }
      if (Number(payment.amount) !== BOOST_PAISE) {
        return jsonResponse({ success: false, error: 'Payment amount does not match this boost' }, 400)
      }

      const { data: boost, error: boostError } = await admin
        .from('meal_boosts')
        .select('id, meal_id, chef_id, status, razorpay_order_id, ends_at')
        .eq('id', boostId)
        .maybeSingle()
      if (boostError || !boost) {
        return jsonResponse({ success: false, error: 'Boost not found' }, 404)
      }
      if (boost.chef_id !== user.id) {
        return jsonResponse({ success: false, error: 'Unauthorized' }, 403)
      }
      if (boost.razorpay_order_id !== orderId) {
        return jsonResponse({ success: false, error: 'Order does not match this boost' }, 400)
      }

      const endsAt = boost.ends_at ?? boostEndsAtIso()
      if (boost.status !== 'paid') {
        const { error: updateError } = await admin
          .from('meal_boosts')
          .update({
            status: 'paid',
            razorpay_payment_id: paymentId,
            starts_at: new Date().toISOString(),
            ends_at: endsAt,
          })
          .eq('id', boostId)
        if (updateError) throw new Error(updateError.message)
      }

      const { error: mealError } = await admin
        .from('meals')
        .update({ boosted_until: endsAt })
        .eq('id', boost.meal_id)
        .eq('chef_id', user.id)
      if (mealError) throw new Error(mealError.message)

      return jsonResponse({ success: true, boosted_until: endsAt })
    }

    const mealId = String(body.meal_id ?? '')
    if (!mealId) return jsonResponse({ success: false, error: 'Missing meal' }, 400)

    const { data: meal, error: mealError } = await admin
      .from('meals')
      .select('id, chef_id, title, status, quantity, boosted_until')
      .eq('id', mealId)
      .maybeSingle()
    if (mealError || !meal) return jsonResponse({ success: false, error: 'Meal not found' }, 404)
    if (meal.chef_id !== user.id) {
      return jsonResponse({ success: false, error: 'Only the kitchen that owns this dish can boost it' }, 403)
    }

    const status = String(meal.status ?? '').toLowerCase().trim()
    const quantity = Number(meal.quantity) || 0
    if (status === 'paused') {
      return jsonResponse({
        success: false,
        error: 'Turn the dish ON in Menu before boosting it',
      }, 400)
    }
    if (quantity <= 0) {
      return jsonResponse({ success: false, error: 'Restock the dish before boosting it' }, 400)
    }
    // Sold out / other leftovers still show as ON in Menu when not Paused.
    // Normalize to Available so a restocked plate can be boosted.
    if (status !== 'available') {
      const { error: publishError } = await admin
        .from('meals')
        .update({ status: 'Available' })
        .eq('id', mealId)
        .eq('chef_id', user.id)
      if (publishError) {
        return jsonResponse({
          success: false,
          error: `Publish the dish before boosting it (now: ${meal.status || 'unknown'})`,
        }, 400)
      }
    }
    if (meal.boosted_until && new Date(String(meal.boosted_until)).getTime() > Date.now()) {
      return jsonResponse({ success: false, error: 'This dish is already boosted today' }, 400)
    }

    const endsAt = boostEndsAtIso()
    const rzpOrder = await createRazorpayOrder(BOOST_PAISE, `boost-${mealId.slice(0, 8)}`, {
      kind: 'meal_boost',
      meal_id: mealId,
      chef_id: user.id,
    })

    const { data: inserted, error: insertError } = await admin
      .from('meal_boosts')
      .insert({
        meal_id: mealId,
        chef_id: user.id,
        amount_paise: BOOST_PAISE,
        status: 'pending',
        ends_at: endsAt,
        razorpay_order_id: rzpOrder.id,
      })
      .select('id')
      .single()
    if (insertError || !inserted) throw new Error(insertError?.message || 'Could not start boost')

    return jsonResponse({
      success: true,
      boost_id: inserted.id,
      order_id: rzpOrder.id,
      amount: BOOST_PAISE,
      currency: 'INR',
      ends_at: endsAt,
    })
  } catch (err) {
    return jsonResponse({ success: false, error: err.message ?? 'Could not start boost' }, 400)
  }
})
