import 'package:flutter_test/flutter_test.dart';
import 'package:hotpotchef_new/utils/helpers.dart';

void main() {
  group('sold-out checkout copy', () {
    test('detects server sold_out code', () {
      expect(isSoldOutCheckoutError(null, {'code': 'sold_out'}), isTrue);
      expect(isSoldOutCheckoutError('network'), isFalse);
    });

    test('detects meal no longer available', () {
      expect(isSoldOutCheckoutError('One or more meals are no longer available'), isTrue);
    });

    test('does not mention a charge when stock is held before payment', () {
      expect(
        soldOutCheckoutMessage(charged: false),
        contains('Nothing was charged'),
      );
    });

    test('explains refund when capture already happened', () {
      expect(
        soldOutCheckoutMessage(charged: true, refunded: true),
        contains('refunded'),
      );
    });
  });

  group('checkoutCartPayload', () {
    test('keeps chef and meal ids without spreading the cart line id as a meal id', () {
      final payload = checkoutCartPayload([
        {
          'id': 'line_not_a_uuid',
          'chef_id': '11111111-1111-1111-1111-111111111111',
          'meal_id': '22222222-2222-2222-2222-222222222222',
          'title': 'AnyDish',
          'quantity': 1,
          'price': 221,
          'chef_name': 'newchef16',
        },
      ]);
      expect(payload.single['chef_id'], '11111111-1111-1111-1111-111111111111');
      expect(payload.single['source_meal_id'], '22222222-2222-2222-2222-222222222222');
      expect(payload.single.containsKey('rawMealDetails'), isFalse);
    });
  });

  group('checkoutErrorMessage', () {
    test('strips the Exception prefix from record failures', () {
      expect(
        checkoutErrorMessage(Exception('We could not record this order, so the payment was refunded. It should return in 5–7 business days.')),
        'We could not record this order, so the payment was refunded. It should return in 5–7 business days.',
      );
    });
  });
}
