import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/delivery_fee.dart';

void main() {
  test('pickup carts quote zero delivery fee', () {
    expect(
      quoteCheckoutDeliveryFee(cartItems: [
        {'chef_id': 'c1', 'selected_service_type': 'Customer Pickup'},
      ], dropLat: 18.5, dropLng: 73.8),
      0,
    );
  });

  test('delivery without drop-off quotes the base fee', () {
    expect(
      quoteCheckoutDeliveryFee(cartItems: [
        {'chef_id': 'c1', 'service_type': 'Delivery'},
      ]),
      kCheckoutDeliveryBaseFee,
    );
  });

  test('each kitchen without a pin adds the base fee', () {
    expect(
      quoteCheckoutDeliveryFee(
        cartItems: [
          {'chef_id': 'c1', 'service_type': 'Delivery'},
          {'chef_id': 'c2', 'service_type': 'Delivery'},
        ],
        dropLat: 18.52,
        dropLng: 73.85,
      ),
      kCheckoutDeliveryBaseFee * 2,
    );
  });

  test('distance over 3 km adds ₹10 per extra kilometre', () {
    expect(deliveryFeeForDistanceKm(3), 30);
    expect(deliveryFeeForDistanceKm(3.1), 40);
    expect(deliveryFeeForDistanceKm(5), 50);
  });

  test('tips cannot exceed ₹500', () {
    expect(clampCheckoutTip(12), 12);
    expect(clampCheckoutTip(900), 500);
    expect(clampCheckoutTip(-4), 0);
  });
}
