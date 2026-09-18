// lib/services/create_split_order_contract.dart
//
// Shared request contract for the deployed `create-split-order` edge function
// (`supabase/functions/create-split-order/index.ts`). Keep in sync with
// CheckoutScreen — do not send a client-computed total.
//
// Auth: user JWT (Authorization: Bearer). Missing/invalid session → HTTP 401.
// Inventory sold-out → HTTP 400 `{ success: false, code: sold_out }`.
// Kitchen closed → HTTP 400 `{ success: false, code: kitchen_closed }`.
// Rate limit → HTTP 429 `{ success: false, code: rate_limited }`.
//
// Request (Flutter → function), snake_case on the wire:
//   cart_items, customer_email, customer_phone, delivery_address, instructions,
//   dropoff_lat, dropoff_lng, tip_amount, apply_coins, add_membership,
//   membership_plan_id
//
// The function quotes the Razorpay charge from catalog prices + qty + add-ons
// + packaging + delivery + tip − coins + optional membership. `delivery_fee`
// and `total_amount` are ignored if sent.
//
// Success HTTP 200:
//   success, order_id (Razorpay), amount (integer paise), currency,
//   hold_minutes, razorpay_customer_id?

class CreateSplitOrderRequest {
  static const String functionName = 'create-split-order';

  static Map<String, dynamic> toBody({
    required List<Map<String, dynamic>> cartItems,
    required String? customerEmail,
    String? customerPhone,
    String? deliveryAddress,
    String? instructions,
    double? dropoffLat,
    double? dropoffLng,
    required num tipAmount,
    required bool applyCoins,
    bool addMembership = false,
    String? membershipPlanId,
  }) {
    return {
      'cart_items': cartItems,
      'customer_email': customerEmail,
      'customer_phone': customerPhone,
      'delivery_address': deliveryAddress,
      'instructions': instructions,
      'dropoff_lat': dropoffLat,
      'dropoff_lng': dropoffLng,
      'tip_amount': tipAmount,
      'apply_coins': applyCoins,
      'add_membership': addMembership,
      'membership_plan_id': membershipPlanId,
    };
  }
}
