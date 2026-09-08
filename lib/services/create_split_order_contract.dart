// lib/services/create_split_order_contract.dart
//
// Shared request contract for the `create-split-order` edge function.
// Keep this in sync with supabase/functions/create-split-order/index.ts.
//
// Request (Flutter → function):
//   cart_items      – line items (mealId / meal_id / source_meal_id, quantity,
//                     selectedAddOns). Multiple items / chefs are allowed.
//   customer_email  – signed-in email; used as a coins-lookup fallback
//   delivery_fee    – client-computed delivery fee in INR (server clamps)
//   tip_amount      – driver tip in INR (server clamps)
//   apply_coins     – redeem HotPot coins against the server-computed subtotal
//
// The function recomputes the Razorpay charge from meals-table prices + qty +
// add-ons + packaging + delivery_fee + tip − coins. It does NOT charge a
// client-supplied `total_amount` (that field is ignored if sent).
//
// Success response:
//   success, order_id (Razorpay), amount (integer paise), currency, chef_transfer

class CreateSplitOrderRequest {
  static const String functionName = 'create-split-order';

  static Map<String, dynamic> toBody({
    required List<Map<String, dynamic>> cartItems,
    required String? customerEmail,
    required double deliveryFee,
    required num tipAmount,
    required bool applyCoins,
  }) {
    return {
      'cart_items': cartItems,
      'customer_email': customerEmail,
      'delivery_fee': deliveryFee,
      'tip_amount': tipAmount,
      'apply_coins': applyCoins,
    };
  }
}
