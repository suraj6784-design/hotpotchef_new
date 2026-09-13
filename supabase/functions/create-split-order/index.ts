// supabase/functions/create-split-order/index.ts
//
// Contract (keep in sync with lib/services/create_split_order_contract.dart):
// Request: { cart_items, customer_email, delivery_fee, tip_amount, apply_coins }
//   - cart_items may contain multiple meals / chefs (mealId | meal_id | source_meal_id)
//   - client `total_amount` / `meal_id` are NOT used to set the charge
//   - amount is recomputed from meals-table prices + qty + add-ons +
//     packaging + clamped delivery_fee/tip − server coin balance
//   - calculate_cart_total RPC is used for packaging_fee (and food fallback)
// Response: { success, order_id, amount (paise), currency, chef_transfer,
//             transfer_status, transfers?, breakdown? }
//
// Route transfers: attached when RAZORPAY_KEY_ID + RAZORPAY_KEY_SECRET are set
// AND the chef has a real linked account (acc_* that is not acc_mock_*).
// Otherwise transfer_status is an explicit skip reason (see route_transfers.ts).
//
// Limitation: payment metadata is still written onto catalog `meals` rows
// (pre-existing schema). For multi-item carts the same Razorpay order_id and
// order-level fee/payout totals are stamped on every meal in the cart.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { handleCreateSplitOrder, jsonResponse } from "./handler.ts"

serve(async (req) => {
  try {
    return await handleCreateSplitOrder(req)
  } catch (err) {
    const message = err instanceof Error ? err.message : "Payment initialization failed"
    return jsonResponse({ error: message }, 400)
  }
})
