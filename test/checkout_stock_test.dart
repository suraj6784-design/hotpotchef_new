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
}
